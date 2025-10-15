package domain

type Folder struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	CreatedAt   int64    `json:"createdAt"`
	UpdatedAt   int64    `json:"updatedAt"`
	DocumentIDs []string `json:"documentIds"`
}

type Document struct {
	ID                string `json:"id"`
	FolderID          string `json:"folderId"`
	Title             string `json:"title"`
	Transcription     string `json:"transcription"`
	Summary           string `json:"summary"`
	Course            string `json:"course"`
	AudioPath         string `json:"audioPath"`
	OriginalAudioPath string `json:"originalAudioPath,omitempty"`
	ProcessingStatus  string `json:"processingStatus"`
	ProcessingError   string `json:"processingError,omitempty"`
	PDFPath           string `json:"pdfPath,omitempty"`
	SourceType        string `json:"sourceType"`
	CreatedAt         int64  `json:"createdAt"`
	UpdatedAt         int64  `json:"updatedAt"`
}

const (
	ProcessingStatusPending    = "pending"
	ProcessingStatusProcessing = "processing"
	ProcessingStatusCompleted  = "completed"
	ProcessingStatusFailed     = "failed"
)
