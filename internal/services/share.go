package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"time"

	"myProfessor/internal/config"
)

func SignURL(path string, expiresAt int64, secret string) string {
	signature := computeSignature(path, expiresAt, secret)
	return fmt.Sprintf("%s?exp=%d&sig=%s", path, expiresAt, signature)
}

func ValidateSignature(path string, expiresAt int64, signature, secret string) bool {
	expected := computeSignature(path, expiresAt, secret)
	return hmac.Equal([]byte(signature), []byte(expected))
}

type ShareService struct {
	secret  string
	baseURL string
	ttl     time.Duration
}

func NewShareService(cfg config.Config) *ShareService {
	return &ShareService{
		secret:  cfg.ShareSecret,
		baseURL: cfg.BaseURL,
		ttl:     cfg.ShareTTL,
	}
}

func (s *ShareService) Generate(docID string) (string, time.Time, error) {
	expiresAt := time.Now().Add(s.ttl)
	path := fmt.Sprintf("/pdf/%s", docID)
	signedPath := SignURL(path, expiresAt.Unix(), s.secret)

	return s.baseURL + signedPath, expiresAt, nil
}

func (s *ShareService) Validate(path string, expires int64, signature string) bool {
	return ValidateSignature(path, expires, signature, s.secret)
}

func computeSignature(path string, expiresAt int64, secret string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(fmt.Sprintf("%s:%d", path, expiresAt)))
	sig := h.Sum(nil)
	return base64.URLEncoding.WithPadding(base64.NoPadding).EncodeToString(sig)
}
