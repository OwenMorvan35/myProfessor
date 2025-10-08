package main

import (
	"log"

	"github.com/joho/godotenv"

	"myProfessor/internal/config"
	httpserver "myProfessor/internal/http"
)

func main() {
	_ = godotenv.Load()

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	srv, err := httpserver.NewServer(cfg)
	if err != nil {
		log.Fatalf("failed to create server: %v", err)
	}

	if err := srv.Run(); err != nil {
		log.Fatalf("server stopped with error: %v", err)
	}
}
