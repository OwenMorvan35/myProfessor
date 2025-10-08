package services

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jung-kurt/gofpdf/v2"

	"myProfessor/internal/domain"
)

type PDFService struct{}

func NewPDFService() *PDFService {
	return &PDFService{}
}

func (s *PDFService) GeneratePDF(doc domain.Document, folder domain.Folder, outPath string) error {
	if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
		return fmt.Errorf("ensure pdf directory: %w", err)
	}

	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.SetTitle(fmt.Sprintf("Cours %s", doc.ID), false)
	pdf.SetAuthor("myProfessor", false)
	pdf.AddPage()

	title := doc.Title
	if strings.TrimSpace(title) == "" {
		title = "Cours"
	}

	createdAt := time.Unix(doc.CreatedAt, 0).Local()

	pdf.SetFont("Helvetica", "B", 18)
	pdf.Cell(0, 10, title)
	pdf.Ln(12)

	pdf.SetFont("Helvetica", "", 12)
	folderLine := "Dossier : Aucun"
	if folder.ID != "" {
		folderName := folder.Name
		if strings.TrimSpace(folderName) == "" {
			folderName = folder.ID
		}
		folderLine = fmt.Sprintf("Dossier : %s", folderName)
	}
	pdf.Cell(0, 6, folderLine)
	pdf.Ln(6)

	pdf.Cell(0, 6, fmt.Sprintf("Créé le : %s", createdAt.Format("02/01/2006 15:04")))
	pdf.Ln(12)

	s.writeSection(pdf, "Transcription", doc.Transcription, false)
	pdf.Ln(8)
	s.writeSection(pdf, "Résumé", doc.Summary, true)

	if err := pdf.OutputFileAndClose(outPath); err != nil {
		return fmt.Errorf("write pdf: %w", err)
	}

	return nil
}

func (s *PDFService) writeSection(pdf *gofpdf.Fpdf, title, content string, bullet bool) {
	pdf.SetFont("Helvetica", "B", 14)
	pdf.Cell(0, 8, title)
	pdf.Ln(10)

	pdf.SetFont("Helvetica", "", 12)

	lines := strings.Split(strings.TrimSpace(content), "\n")
	if len(lines) == 0 {
		pdf.MultiCell(0, 6, "(vide)", "", "L", false)
		return
	}

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		text := line
		if bullet {
			text = fmt.Sprintf("• %s", line)
		}
		pdf.MultiCell(0, 6, text, "", "L", false)
	}
}
