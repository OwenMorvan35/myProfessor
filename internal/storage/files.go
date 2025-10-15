package storage

import (
	"bytes"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

type FileManager struct {
	baseDir        string
	audioDir       string
	pdfDir         string
	maxUploadBytes int64
}

const (
	ffmpegBinary     = "ffmpeg"
	maxWhisperBytes  = 25 * 1024 * 1024
	compressedSuffix = "_compressed"
	compressedExt    = ".mp3"
)

var compressionProfiles = []struct {
	bitrate    string
	sampleRate string
}{
	{bitrate: "128k", sampleRate: "44100"},
	{bitrate: "96k", sampleRate: "32000"},
	{bitrate: "64k", sampleRate: "22050"},
	{bitrate: "48k", sampleRate: "16000"},
	{bitrate: "32k", sampleRate: "12000"},
}

var mimeExtensionFallback = map[string]string{
	"audio/mpeg":      ".mp3",
	"audio/mp3":       ".mp3",
	"audio/mp4":       ".m4a",
	"audio/x-m4a":     ".m4a",
	"audio/wav":       ".wav",
	"audio/x-wav":     ".wav",
	"audio/webm":      ".webm",
	"audio/ogg":       ".webm",
	"video/mp4":       ".m4a",
	"video/quicktime": ".m4a",
}

func NewFileManager(baseDir string, maxUploadBytes int64) (*FileManager, error) {
	fm := &FileManager{
		baseDir:        baseDir,
		audioDir:       filepath.Join(baseDir, "audio"),
		pdfDir:         filepath.Join(baseDir, "pdf"),
		maxUploadBytes: maxUploadBytes,
	}

	dirs := []string{fm.baseDir, fm.audioDir, fm.pdfDir}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return nil, fmt.Errorf("create dir %s: %w", dir, err)
		}
	}

	return fm, nil
}

func (fm *FileManager) SaveUploadedAudio(file multipart.File, filename string) (string, error) {
	sample := make([]byte, 512)
	n, err := file.Read(sample)
	if err != nil && err != io.EOF {
		return "", fmt.Errorf("read audio sample: %w", err)
	}
	sample = sample[:n]

	ext := normalizeExtension(filename)
	contentType := strings.ToLower(http.DetectContentType(sample))
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	if ext == "" {
		ext = fallbackExtension(contentType)
	}

	if ext == "" {
		ext = ".bin"
	}

	if !strings.HasPrefix(ext, ".") {
		ext = "." + ext
	}

	if contentType != "application/octet-stream" && !strings.HasPrefix(contentType, "audio/") && !strings.HasPrefix(contentType, "video/") {
		fmt.Printf("warning: unrecognized audio mime type %s, continuing with extension %s\n", contentType, ext)
	}

	id := uuid.NewString()
	filenameOnDisk := fmt.Sprintf("%s%s", id, ext)
	path := filepath.Join(fm.audioDir, filenameOnDisk)

	if err := fm.writeWithLimit(path, sample, file); err != nil {
		return "", err
	}

	return path, nil
}

func (fm *FileManager) SavePDF(id string, r io.Reader) (string, error) {
	path := filepath.Join(fm.pdfDir, fmt.Sprintf("%s.pdf", id))
	out, err := os.Create(path)
	if err != nil {
		return "", fmt.Errorf("create pdf file: %w", err)
	}
	defer out.Close()

	if _, err := io.Copy(out, r); err != nil {
		os.Remove(path)
		return "", fmt.Errorf("write pdf file: %w", err)
	}

	return path, nil
}

func (fm *FileManager) PDFPath(id string) string {
	return filepath.Join(fm.pdfDir, fmt.Sprintf("%s.pdf", id))
}

func (fm *FileManager) writeWithLimit(path string, sample []byte, file multipart.File) error {
	if fm.maxUploadBytes > 0 && int64(len(sample)) > fm.maxUploadBytes {
		return fmt.Errorf("audio file exceeds maximum size")
	}

	out, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create audio file: %w", err)
	}

	total := int64(0)

	cleanup := func(err error) error {
		out.Close()
		os.Remove(path)
		return err
	}

	if len(sample) > 0 {
		if _, err := out.Write(sample); err != nil {
			return cleanup(fmt.Errorf("write audio sample: %w", err))
		}
		total += int64(len(sample))
	}

	buf := make([]byte, 32*1024)
	for {
		if fm.maxUploadBytes > 0 && total >= fm.maxUploadBytes {
			return cleanup(fmt.Errorf("audio file exceeds maximum size"))
		}

		n, err := file.Read(buf)
		if n > 0 {
			total += int64(n)
			if fm.maxUploadBytes > 0 && total > fm.maxUploadBytes {
				return cleanup(fmt.Errorf("audio file exceeds maximum size"))
			}
			if _, werr := out.Write(buf[:n]); werr != nil {
				return cleanup(fmt.Errorf("write audio file: %w", werr))
			}
		}

		if err == io.EOF {
			break
		}
		if err != nil {
			return cleanup(fmt.Errorf("read audio content: %w", err))
		}
	}

	if err := out.Close(); err != nil {
		os.Remove(path)
		return fmt.Errorf("close audio file: %w", err)
	}

	return nil
}

func normalizeExtension(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	if ext == "" {
		return ext
	}

	ext = strings.TrimSpace(ext)
	if !strings.HasPrefix(ext, ".") {
		ext = "." + ext
	}
	return ext
}

func fallbackExtension(contentType string) string {
	if ext, ok := mimeExtensionFallback[contentType]; ok {
		return ext
	}
	exts, err := mime.ExtensionsByType(contentType)
	if err == nil && len(exts) > 0 {
		return exts[0]
	}
	return ""
}

func (fm *FileManager) CompressAudio(inputPath string) (string, error) {
	if inputPath == "" {
		return "", fmt.Errorf("no audio path provided for compression")
	}

	if _, err := exec.LookPath(ffmpegBinary); err != nil {
		return "", fmt.Errorf("ffmpeg not found in PATH: %w", err)
	}

	base := strings.TrimSuffix(filepath.Base(inputPath), filepath.Ext(inputPath))
	output := filepath.Join(fm.audioDir, base+compressedSuffix+compressedExt)

	if _, err := os.Stat(output); err == nil {
		if err := fm.ensureWithinWhisperLimit(output); err != nil {
			return "", err
		}
		return output, nil
	}

	var lastErr error
	for idx, profile := range compressionProfiles {
		if idx > 0 {
			_ = os.Remove(output)
		}

		args := []string{
			"-y",
			"-i", inputPath,
			"-vn",
			"-ac", "1",
			"-acodec", "libmp3lame",
			"-b:a", profile.bitrate,
		}
		if profile.sampleRate != "" {
			args = append(args, "-ar", profile.sampleRate)
		}
		args = append(args, output)

		cmd := exec.Command(ffmpegBinary, args...)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			lastErr = fmt.Errorf("compress audio: %w: %s", err, strings.TrimSpace(stderr.String()))
			continue
		}

		if err := fm.ensureWithinWhisperLimit(output); err != nil {
			lastErr = err
			_ = os.Remove(output)
			continue
		}

		return output, nil
	}

	if lastErr != nil {
		return "", lastErr
	}
	return "", fmt.Errorf("compressed audio still exceeds Whisper limit after applying fallback profiles")
}

func (fm *FileManager) ensureWithinWhisperLimit(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat compressed audio: %w", err)
	}

	if info.Size() > maxWhisperBytes {
		return fmt.Errorf("compressed audio size %.2f MB exceeds Whisper limit of %.2f MB",
			float64(info.Size())/1024.0/1024.0,
			float64(maxWhisperBytes)/1024.0/1024.0)
	}
	return nil
}
