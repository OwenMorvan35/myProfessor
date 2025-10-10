package services

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"myProfessor/internal/config"
)

const (
	transcriptionEndpoint = "https://api.openai.com/v1/audio/transcriptions"
	summaryEndpoint       = "https://api.openai.com/v1/chat/completions"
	requestTimeout        = 5 * time.Minute
)

var allowedAudioMIMEs = map[string]struct{}{
	"audio/webm":  {},
	"audio/mpeg":  {},
	"audio/mp4":   {},
	"audio/x-m4a": {},
	"audio/wav":   {},
}

const summarySystemPrompt = "Tu es un assistant pédagogique. Résume ce cours en bullet points clairs. Sépare Définitions, Concepts, Exemples."
const courseSystemPrompt = "Tu es un enseignant, transforme cette transcription en un cours complet, clair et structuré, avec titres et sous-parties."

type OpenAIService struct {
	apiKey          string
	reqTimeout      time.Duration
	transcribeModel string
	summaryModel    string
	httpClient      *http.Client
}

func NewOpenAIService(cfg config.Config) *OpenAIService {
	return &OpenAIService{
		apiKey:          cfg.OpenAIAPIKey,
		reqTimeout:      requestTimeout,
		transcribeModel: cfg.OpenAIModelTranscribe,
		summaryModel:    cfg.OpenAIModelSummary,
		httpClient:      &http.Client{Timeout: requestTimeout},
	}
}

func (s *OpenAIService) Transcribe(r io.Reader, filename string, mime string) (string, error) {
	if err := s.ensureAPIKey(); err != nil {
		return "", err
	}

	if mime != "" {
		if _, ok := allowedAudioMIMEs[strings.ToLower(mime)]; !ok {
			return "", fmt.Errorf("unsupported audio mime type: %s", mime)
		}
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return "", fmt.Errorf("create multipart file: %w", err)
	}
	if _, err := io.Copy(part, r); err != nil {
		return "", fmt.Errorf("copy audio data: %w", err)
	}

	if err := writer.WriteField("model", s.transcribeModel); err != nil {
		return "", fmt.Errorf("write model field: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, transcriptionEndpoint, body)
	if err != nil {
		return "", fmt.Errorf("create transcription request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := s.do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		return "", s.decodeAPIError(resp)
	}

	var payload struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", fmt.Errorf("decode transcription response: %w", err)
	}

	return strings.TrimSpace(payload.Text), nil
}

func (s *OpenAIService) Summarize(transcription string) (string, error) {
	return s.invokeChatCompletion(summarySystemPrompt, transcription, "")
}

func (s *OpenAIService) GenerateCourse(transcription, instructions string) (string, error) {
	return s.invokeChatCompletion(courseSystemPrompt, transcription, instructions)
}

func (s *OpenAIService) invokeChatCompletion(systemPrompt, transcription, instructions string) (string, error) {
	if err := s.ensureAPIKey(); err != nil {
		return "", err
	}

	contentBuilder := strings.Builder{}
	contentBuilder.WriteString(transcription)
	if strings.TrimSpace(instructions) != "" {
		contentBuilder.WriteString("\n\nInstructions supplémentaires :\n")
		contentBuilder.WriteString(instructions)
	}

	payload := map[string]any{
		"model": s.summaryModel,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": contentBuilder.String()},
		},
		"temperature": 0.2,
	}

	buf := &bytes.Buffer{}
	if err := json.NewEncoder(buf).Encode(payload); err != nil {
		return "", fmt.Errorf("encode payload: %w", err)
	}

	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, summaryEndpoint, buf)
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		return "", s.decodeAPIError(resp)
	}

	var response struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}

	if len(response.Choices) == 0 {
		return "", errors.New("no choices returned")
	}

	return strings.TrimSpace(response.Choices[0].Message.Content), nil
}

func (s *OpenAIService) TranscribeAudio(ctx context.Context, path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open audio file: %w", err)
	}
	defer file.Close()

	return s.Transcribe(file, filepath.Base(path), "")
}

func (s *OpenAIService) SummarizeText(ctx context.Context, transcription string) (string, error) {
	return s.Summarize(transcription)
}

func (s *OpenAIService) do(req *http.Request) (*http.Response, error) {
	ctx, cancel := context.WithTimeout(req.Context(), s.reqTimeout)
	req = req.WithContext(ctx)

	resp, err := s.httpClient.Do(req)
	cancel()
	if err != nil {
		return nil, fmt.Errorf("openai request failed: %w", err)
	}

	return resp, nil
}

func (s *OpenAIService) decodeAPIError(resp *http.Response) error {
	var apiErr struct {
		Error struct {
			Message string `json:"message"`
			Type    string `json:"type"`
			Code    any    `json:"code"`
		} `json:"error"`
	}

	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	resp.Body = io.NopCloser(bytes.NewBuffer(body))

	if err := json.Unmarshal(body, &apiErr); err == nil && apiErr.Error.Message != "" {
		return fmt.Errorf("openai api error: status %d type %s message %s", resp.StatusCode, apiErr.Error.Type, apiErr.Error.Message)
	}

	return fmt.Errorf("openai api error: status %d body %s", resp.StatusCode, string(body))
}

func (s *OpenAIService) ensureAPIKey() error {
	if strings.TrimSpace(s.apiKey) == "" {
		return errors.New("openai api key is not configured")
	}
	return nil
}
