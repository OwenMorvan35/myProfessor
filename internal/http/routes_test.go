package http

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"myProfessor/internal/config"
	"myProfessor/internal/domain"
	"myProfessor/internal/services"
	"myProfessor/internal/storage"
)

func setupTestServer(t *testing.T) (*gin.Engine, *storage.Store) {
	t.Helper()

	tmpDir := t.TempDir()

	cfg := config.Config{
		Port:                  "8080",
		OpenAIModelTranscribe: "whisper-1",
		OpenAIModelSummary:    "gpt-4o-mini",
		BaseURL:               "http://localhost:8080",
		ShareSecret:           "secret",
		ShareTTL:              time.Minute,
		MaxUploadBytes:        1 * 1024 * 1024,
		DataDir:               tmpDir,
	}

	fm, err := storage.NewFileManager(cfg.DataDir, cfg.MaxUploadBytes)
	if err != nil {
		t.Fatalf("file manager: %v", err)
	}

	store, err := storage.NewStore(cfg.DataDir)
	if err != nil {
		t.Fatalf("store: %v", err)
	}

	openai := services.NewOpenAIService(cfg)
	pdf := services.NewPDFService()
	share := services.NewShareService(cfg)

	engine := gin.New()
	engine.Use(gin.Recovery())
	api := NewAPI(cfg, fm, store, openai, pdf, share)
	registerRoutes(engine, api)

	return engine, store
}

func TestHealthHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, _ := setupTestServer(t)

	req := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	rec := httptest.NewRecorder()

	engine.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}

	if ok, exists := body["ok"].(bool); !exists || !ok {
		t.Fatalf("expected ok=true, body=%v", body)
	}
}

func TestUploadMissingFile(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, store := setupTestServer(t)

	folder, err := store.CreateFolder("Test")
	if err != nil {
		t.Fatalf("create folder: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/folders/"+folder.ID+"/documents/upload", nil)
	rec := httptest.NewRecorder()

	engine.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}

	if body["error"] == nil {
		t.Fatalf("expected error message in response")
	}
}

func TestShareLinkValidation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine, store := setupTestServer(t)

	doc, err := store.CreateDocument(domain.Document{
		Title:         "Doc",
		Transcription: "text",
		Summary:       "summary",
		PDFPath:       "fake.pdf",
	})
	if err != nil {
		t.Fatalf("create document: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/documents/"+doc.ID+"/share", strings.NewReader("{}"))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	engine.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode share response: %v", err)
	}

	if body.URL == "" {
		t.Fatalf("expected url in response")
	}

	invalidReq := httptest.NewRequest(http.MethodGet, "/pdf/"+doc.ID+"?exp=9999999999&sig=invalid", nil)
	invalidRec := httptest.NewRecorder()

	engine.ServeHTTP(invalidRec, invalidReq)

	if invalidRec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for invalid signature, got %d", invalidRec.Code)
	}

	expiredReq := httptest.NewRequest(http.MethodGet, "/pdf/"+doc.ID+"?exp=1&sig=whatever", nil)
	expiredRec := httptest.NewRecorder()

	engine.ServeHTTP(expiredRec, expiredReq)

	if expiredRec.Code != http.StatusGone {
		t.Fatalf("expected 410 for expired link, got %d", expiredRec.Code)
	}
}
