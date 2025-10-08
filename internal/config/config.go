package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

type Config struct {
	Port                  string
	OpenAIAPIKey          string
	OpenAIModelTranscribe string
	OpenAIModelSummary    string
	BaseURL               string
	ShareSecret           string
	ShareTTL              time.Duration
	MaxUploadBytes        int64
	DataDir               string
}

func LoadConfig() (Config, error) {
	cfg := Config{}

	cfg.Port = envOrDefault("PORT", "8080")
	cfg.OpenAIAPIKey = os.Getenv("OPENAI_API_KEY")
	cfg.OpenAIModelTranscribe = envOrDefault("OPENAI_MODEL_TRANSCRIBE", "whisper-1")
	cfg.OpenAIModelSummary = envOrDefault("OPENAI_MODEL_SUMMARY", "gpt-4o-mini")

	cfg.BaseURL = envOrDefault("BASE_URL", fmt.Sprintf("http://localhost:%s", cfg.Port))
	cfg.ShareSecret = envOrDefault("SHARE_SECRET", "change-me")
	cfg.DataDir = envOrDefault("DATA_DIR", "data")

	shareTTLSeconds, err := parseIntEnv("SHARE_TTL_SECONDS", 86400)
	if err != nil {
		return Config{}, fmt.Errorf("parse SHARE_TTL_SECONDS: %w", err)
	}
	cfg.ShareTTL = time.Duration(shareTTLSeconds) * time.Second

	maxUploadMB, err := parseIntEnv("MAX_UPLOAD_MB", 50)
	if err != nil {
		return Config{}, fmt.Errorf("parse MAX_UPLOAD_MB: %w", err)
	}
	cfg.MaxUploadBytes = maxUploadMB * 1024 * 1024

	absDataDir, err := filepath.Abs(cfg.DataDir)
	if err != nil {
		return Config{}, fmt.Errorf("resolve data dir: %w", err)
	}
	cfg.DataDir = absDataDir

	return cfg, nil
}

func envOrDefault(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return fallback
}

func parseIntEnv(key string, fallback int64) (int64, error) {
	value := envOrDefault(key, "")
	if value == "" {
		return fallback, nil
	}

	num, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return 0, err
	}
	return num, nil
}
