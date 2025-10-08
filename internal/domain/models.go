package domain

type Folder struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	CreatedAt   int64    `json:"createdAt"`
	UpdatedAt   int64    `json:"updatedAt"`
	DocumentIDs []string `json:"documentIds"`
}

type Document struct {
	ID            string `json:"id"`
	FolderID      string `json:"folderId"`
	Title         string `json:"title"`
	Transcription string `json:"transcription"`
	Summary       string `json:"summary"`
	AudioPath     string `json:"audioPath"`
	PDFPath       string `json:"pdfPath,omitempty"`
	SourceType    string `json:"sourceType"`
	CreatedAt     int64  `json:"createdAt"`
	UpdatedAt     int64  `json:"updatedAt"`
}
