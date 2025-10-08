package http

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"myProfessor/internal/config"
	"myProfessor/internal/services"
	"myProfessor/internal/storage"
)

type Server struct {
	engine *gin.Engine
	cfg    config.Config
}

func NewServer(cfg config.Config) (*Server, error) {
	gin.SetMode(gin.ReleaseMode)

	fm, err := storage.NewFileManager(cfg.DataDir, cfg.MaxUploadBytes)
	if err != nil {
		return nil, fmt.Errorf("init file manager: %w", err)
	}

	store, err := storage.NewStore(cfg.DataDir)
	if err != nil {
		return nil, fmt.Errorf("init store: %w", err)
	}
	openaiSvc := services.NewOpenAIService(cfg)
	pdfSvc := services.NewPDFService()
	shareSvc := services.NewShareService(cfg)

	engine := gin.New()
	engine.Use(gin.Recovery())
	engine.Use(RequestLogger())
	engine.Use(MaxBodySize(cfg.MaxUploadBytes))
	engine.Use(CORS())

	api := NewAPI(cfg, fm, store, openaiSvc, pdfSvc, shareSvc)
	registerRoutes(engine, api)

	return &Server{engine: engine, cfg: cfg}, nil
}

func (s *Server) Run() error {
	addr := fmt.Sprintf(":%s", s.cfg.Port)
	return s.engine.Run(addr)
}
