package http

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"myProfessor/internal/config"
	"myProfessor/internal/domain"
	"myProfessor/internal/services"
	"myProfessor/internal/storage"
)

type API struct {
	cfg    config.Config
	files  *storage.FileManager
	store  *storage.Store
	openai *services.OpenAIService
	pdf    *services.PDFService
	share  *services.ShareService
}

func NewAPI(cfg config.Config, fm *storage.FileManager, store *storage.Store, openai *services.OpenAIService, pdf *services.PDFService, share *services.ShareService) *API {
	return &API{cfg: cfg, files: fm, store: store, openai: openai, pdf: pdf, share: share}
}

func registerRoutes(r *gin.Engine, api *API) {
	apiGroup := r.Group("/api")
	{
		apiGroup.GET("/health", api.handleHealth)

		apiGroup.GET("/folders", api.handleListFolders)
		apiGroup.POST("/folders", api.handleCreateFolder)
		apiGroup.PATCH("/folders/:id", api.handleRenameFolder)
		apiGroup.DELETE("/folders/:id", api.handleDeleteFolder)

		apiGroup.GET("/folders/:id/documents", api.handleListDocumentsByFolder)
		apiGroup.POST("/folders/:id/documents/upload", api.handleUploadDocument)

		apiGroup.GET("/documents/:id", api.handleGetDocument)
		apiGroup.DELETE("/documents/:id", api.handleDeleteDocument)
		apiGroup.POST("/documents/:id/pdf", api.handleGeneratePDF)
		apiGroup.POST("/documents/:id/share", api.handleShareDocument)
		apiGroup.POST("/documents/:id/course", api.handleGenerateCourse)
	}

	r.GET("/pdf/:id", api.handleServePDF)
}

func (a *API) handleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (a *API) handleListFolders(c *gin.Context) {
	folders := a.store.ListFolders()
	c.JSON(http.StatusOK, folders)
}

func (a *API) handleCreateFolder(c *gin.Context) {
	var payload struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}

	payload.Name = strings.TrimSpace(payload.Name)
	folder, err := a.store.CreateFolder(payload.Name)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}

	c.JSON(http.StatusCreated, folder)
}

func (a *API) handleRenameFolder(c *gin.Context) {
	var payload struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil {
		respondError(c, http.StatusBadRequest, err)
		return
	}

	payload.Name = strings.TrimSpace(payload.Name)
	folder, err := a.store.RenameFolder(c.Param("id"), payload.Name)
	if err != nil {
		status := http.StatusNotFound
		if !strings.Contains(err.Error(), "not found") {
			status = http.StatusInternalServerError
		}
		respondMessage(c, status, err.Error())
		return
	}

	c.JSON(http.StatusOK, folder)
}

func (a *API) handleDeleteFolder(c *gin.Context) {
	if err := a.store.DeleteFolder(c.Param("id")); err != nil {
		status := http.StatusNotFound
		if !strings.Contains(err.Error(), "not found") {
			status = http.StatusInternalServerError
		}
		respondMessage(c, status, err.Error())
		return
	}

	c.Status(http.StatusNoContent)
}

func (a *API) handleListDocumentsByFolder(c *gin.Context) {
	if _, err := a.store.GetFolder(c.Param("id")); err != nil {
		respondMessage(c, http.StatusNotFound, "folder not found")
		return
	}

	docs := a.store.ListDocumentsByFolder(c.Param("id"))
	c.JSON(http.StatusOK, docs)
}

func (a *API) handleGetDocument(c *gin.Context) {
	doc, err := a.store.GetDocument(c.Param("id"))
	if err != nil {
		respondMessage(c, http.StatusNotFound, "document not found")
		return
	}

	c.JSON(http.StatusOK, doc)
}

func (a *API) handleDeleteDocument(c *gin.Context) {
	docID := c.Param("id")
	doc, err := a.store.GetDocument(docID)
	if err != nil {
		respondMessage(c, http.StatusNotFound, "document not found")
		return
	}

	if err := a.store.DeleteDocument(docID); err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}

	if doc.AudioPath != "" {
		_ = os.Remove(doc.AudioPath)
	}
	if doc.PDFPath != "" {
		_ = os.Remove(doc.PDFPath)
	}

	c.Status(http.StatusNoContent)
}

func (a *API) handleUploadDocument(c *gin.Context) {
	folderID := c.Param("id")
	if _, err := a.store.GetFolder(folderID); err != nil {
		respondMessage(c, http.StatusNotFound, "folder not found")
		return
	}

	log.Printf("Upload request headers: %#v", c.Request.Header)

	fileHeader, err := c.FormFile("file")
	if err != nil {
		respondMessage(c, http.StatusBadRequest, "missing audio file")
		return
	}
	log.Printf("Received upload: folder=%s filename=%s size=%d", folderID, fileHeader.Filename, fileHeader.Size)

	upload, err := fileHeader.Open()
	if err != nil {
		log.Printf("error opening upload: %v", err)
		respondMessage(c, http.StatusInternalServerError, "unable to read uploaded file")
		return
	}
	defer upload.Close()

	audioPath, err := a.files.SaveUploadedAudio(upload, fileHeader.Filename)
	if err != nil {
		log.Printf("error saving uploaded audio: %v", err)
		respondMessage(c, http.StatusBadRequest, err.Error())
		return
	}
	log.Printf("Audio saved to %s", audioPath)

	ctx := c.Request.Context()
	transcription, err := a.openai.TranscribeAudio(ctx, audioPath)
	if err != nil {
		log.Printf("transcription failed: %v", err)
		respondMessage(c, http.StatusBadGateway, "transcription failed")
		return
	}

	summary, err := a.openai.Summarize(transcription)
	if err != nil {
		log.Printf("summary failed: %v", err)
		respondMessage(c, http.StatusBadGateway, "summary failed")
		return
	}

	doc := domain.Document{
		FolderID:      folderID,
		Title:         strings.TrimSuffix(fileHeader.Filename, filepath.Ext(fileHeader.Filename)),
		Transcription: transcription,
		Summary:       summary,
		AudioPath:     audioPath,
		SourceType:    "upload",
	}

	saved, err := a.store.CreateDocument(doc)
	if err != nil {
		log.Printf("document save failed: %v", err)
		respondMessage(c, http.StatusInternalServerError, "unable to save document")
		return
	}
	log.Printf("Document %s created for folder %s", saved.ID, folderID)

	c.JSON(http.StatusCreated, gin.H{"document": saved})
}

func (a *API) handleGeneratePDF(c *gin.Context) {
	docID := c.Param("id")
	doc, err := a.store.GetDocument(docID)
	if err != nil {
		respondMessage(c, http.StatusNotFound, "document not found")
		return
	}

	folder, _ := a.store.GetFolder(doc.FolderID)

	pdfPath := a.files.PDFPath(doc.ID)
	if err := a.pdf.GeneratePDF(doc, folder, pdfPath); err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}

	doc.PDFPath = pdfPath
	if _, err := a.store.UpdateDocument(doc); err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"pdfPath": pdfPath})
}

func (a *API) handleShareDocument(c *gin.Context) {
	docID := c.Param("id")
	doc, err := a.store.GetDocument(docID)
	if err != nil {
		respondMessage(c, http.StatusNotFound, "document not found")
		return
	}

	if doc.PDFPath == "" {
		respondMessage(c, http.StatusBadRequest, "no pdf available for this document")
		return
	}

	url, expiresAt, err := a.share.Generate(docID)
	if err != nil {
		respondError(c, http.StatusInternalServerError, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"url": url, "expiresAt": expiresAt.UTC()})
}

func (a *API) handleGenerateCourse(c *gin.Context) {
	docID := c.Param("id")
	doc, err := a.store.GetDocument(docID)
	if err != nil {
		respondMessage(c, http.StatusNotFound, "document not found")
		return
	}

	if strings.TrimSpace(doc.Transcription) == "" {
		respondMessage(c, http.StatusBadRequest, "document has no transcription")
		return
	}

	var payload struct {
		Instructions string `json:"instructions"`
	}

	if c.Request.ContentLength > 0 {
		if err := c.ShouldBindJSON(&payload); err != nil {
			respondMessage(c, http.StatusBadRequest, "invalid payload")
			return
		}
	}

	course, err := a.openai.GenerateCourse(doc.Transcription, payload.Instructions)
	if err != nil {
		log.Printf("course generation failed: %v", err)
		respondMessage(c, http.StatusInternalServerError, err.Error())
		return
	}

	c.JSON(http.StatusOK, gin.H{"course": course})
}

func (a *API) handleServePDF(c *gin.Context) {
	docID := c.Param("id")
	expiresParam := c.Query("exp")
	signature := c.Query("sig")

	if expiresParam == "" || signature == "" {
		respondMessage(c, http.StatusBadRequest, "missing signature")
		return
	}

	expires, err := strconv.ParseInt(expiresParam, 10, 64)
	if err != nil {
		respondMessage(c, http.StatusBadRequest, "invalid expiration")
		return
	}

	if expires < time.Now().Unix() {
		respondMessage(c, http.StatusGone, "link expired")
		return
	}

	path := c.Request.URL.Path
	if !a.share.Validate(path, expires, signature) {
		respondMessage(c, http.StatusForbidden, "invalid signature")
		return
	}

	doc, err := a.store.GetDocument(docID)
	if err != nil {
		respondMessage(c, http.StatusNotFound, "document not found")
		return
	}

	pdfPath := doc.PDFPath
	if pdfPath == "" {
		pdfPath = a.files.PDFPath(docID)
	}

	if _, err := os.Stat(pdfPath); err != nil {
		respondMessage(c, http.StatusNotFound, "pdf not found")
		return
	}

	c.Header("Content-Type", "application/pdf")
	c.FileAttachment(pdfPath, filepath.Base(pdfPath))
}

func respondError(c *gin.Context, status int, err error) {
	respondMessage(c, status, err.Error())
}

func respondMessage(c *gin.Context, status int, message string) {
	c.JSON(status, gin.H{"error": message})
}
