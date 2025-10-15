package storage

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"myProfessor/internal/domain"
)

type metaData struct {
	Folders   map[string]domain.Folder   `json:"folders"`
	Documents map[string]domain.Document `json:"documents"`
}

type Store struct {
	mu   sync.RWMutex
	path string
	data metaData
}

func NewStore(baseDir string) (*Store, error) {
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return nil, fmt.Errorf("create data directory: %w", err)
	}

	store := &Store{path: filepath.Join(baseDir, "meta.json")}
	if err := store.Load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *Store) Load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.data = metaData{
		Folders:   map[string]domain.Folder{},
		Documents: map[string]domain.Document{},
	}

	file, err := os.Open(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return s.saveLocked()
	}
	if err != nil {
		return fmt.Errorf("open meta file: %w", err)
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&s.data); err != nil {
		if errors.Is(err, io.EOF) {
			return s.saveLocked()
		}
		return fmt.Errorf("decode meta file: %w", err)
	}

	s.ensureMaps()
	return nil
}

func (s *Store) Save() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.saveLocked()
}

func (s *Store) CreateFolder(name string) (domain.Folder, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.ensureMaps()
	id := uuid.NewString()
	now := time.Now().Unix()
	folder := domain.Folder{
		ID:          id,
		Name:        name,
		CreatedAt:   now,
		UpdatedAt:   now,
		DocumentIDs: []string{},
	}

	s.data.Folders[id] = folder

	if err := s.saveLocked(); err != nil {
		return domain.Folder{}, err
	}

	return folder, nil
}

func (s *Store) ListFolders() []domain.Folder {
	s.mu.RLock()
	defer s.mu.RUnlock()

	folders := make([]domain.Folder, 0, len(s.data.Folders))
	for _, folder := range s.data.Folders {
		folders = append(folders, folder)
	}
	return folders
}

func (s *Store) GetFolder(id string) (domain.Folder, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	folder, ok := s.data.Folders[id]
	if !ok {
		return domain.Folder{}, fmt.Errorf("folder %s not found", id)
	}
	return folder, nil
}

func (s *Store) RenameFolder(id, newName string) (domain.Folder, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	folder, ok := s.data.Folders[id]
	if !ok {
		return domain.Folder{}, fmt.Errorf("folder %s not found", id)
	}

	folder.Name = newName
	folder.UpdatedAt = time.Now().Unix()
	s.data.Folders[id] = folder

	if err := s.saveLocked(); err != nil {
		return domain.Folder{}, err
	}

	return folder, nil
}

func (s *Store) DeleteFolder(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	folder, ok := s.data.Folders[id]
	if !ok {
		return fmt.Errorf("folder %s not found", id)
	}

	for _, docID := range folder.DocumentIDs {
		delete(s.data.Documents, docID)
	}

	delete(s.data.Folders, id)

	return s.saveLocked()
}

func (s *Store) CreateDocument(doc domain.Document) (domain.Document, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.ensureMaps()

	if doc.ID == "" {
		doc.ID = uuid.NewString()
	}
	if doc.ProcessingStatus == "" {
		doc.ProcessingStatus = domain.ProcessingStatusPending
	}
	now := time.Now().Unix()
	if doc.CreatedAt == 0 {
		doc.CreatedAt = now
	}
	doc.UpdatedAt = now

	s.data.Documents[doc.ID] = doc
	s.attachDocumentToFolder(doc.FolderID, doc.ID)

	if err := s.saveLocked(); err != nil {
		return domain.Document{}, err
	}

	return doc, nil
}

func (s *Store) ListDocumentsByFolder(folderID string) []domain.Document {
	s.mu.RLock()
	defer s.mu.RUnlock()

	docs := make([]domain.Document, 0)
	for _, doc := range s.data.Documents {
		if doc.FolderID == folderID {
			docs = append(docs, doc)
		}
	}
	return docs
}

func (s *Store) GetDocument(id string) (domain.Document, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	doc, ok := s.data.Documents[id]
	if !ok {
		return domain.Document{}, fmt.Errorf("document %s not found", id)
	}
	return doc, nil
}

func (s *Store) UpdateDocument(doc domain.Document) (domain.Document, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	existing, ok := s.data.Documents[doc.ID]
	if !ok {
		return domain.Document{}, fmt.Errorf("document %s not found", doc.ID)
	}

	if doc.CreatedAt == 0 {
		doc.CreatedAt = existing.CreatedAt
	}

	if doc.FolderID != existing.FolderID {
		s.detachDocumentFromFolder(existing.FolderID, doc.ID)
		s.attachDocumentToFolder(doc.FolderID, doc.ID)
	}

	if doc.ProcessingStatus == "" {
		doc.ProcessingStatus = existing.ProcessingStatus
	}

	doc.UpdatedAt = time.Now().Unix()
	s.data.Documents[doc.ID] = doc

	if err := s.saveLocked(); err != nil {
		return domain.Document{}, err
	}
	return doc, nil
}

func (s *Store) DeleteDocument(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	doc, ok := s.data.Documents[id]
	if !ok {
		return fmt.Errorf("document %s not found", id)
	}

	s.detachDocumentFromFolder(doc.FolderID, id)

	delete(s.data.Documents, id)

	return s.saveLocked()
}

func (s *Store) saveLocked() error {
	tmp, err := os.CreateTemp(filepath.Dir(s.path), "meta-*.json")
	if err != nil {
		return fmt.Errorf("create temp meta: %w", err)
	}

	encoder := json.NewEncoder(tmp)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(s.data); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return fmt.Errorf("encode meta: %w", err)
	}

	if err := tmp.Close(); err != nil {
		os.Remove(tmp.Name())
		return fmt.Errorf("close temp meta: %w", err)
	}

	if err := os.Rename(tmp.Name(), s.path); err != nil {
		os.Remove(tmp.Name())
		return fmt.Errorf("replace meta file: %w", err)
	}

	return nil
}

func (s *Store) ensureMaps() {
	if s.data.Folders == nil {
		s.data.Folders = map[string]domain.Folder{}
	}
	if s.data.Documents == nil {
		s.data.Documents = map[string]domain.Document{}
	}

	for id, doc := range s.data.Documents {
		if doc.ProcessingStatus == "" {
			status := domain.ProcessingStatusPending
			if strings.TrimSpace(doc.Transcription) != "" {
				status = domain.ProcessingStatusCompleted
			}
			doc.ProcessingStatus = status
			s.data.Documents[id] = doc
		}
	}
}

func (s *Store) attachDocumentToFolder(folderID, docID string) {
	if folderID == "" {
		return
	}

	folder, ok := s.data.Folders[folderID]
	if !ok {
		return
	}

	for _, existing := range folder.DocumentIDs {
		if existing == docID {
			return
		}
	}

	folder.DocumentIDs = append(folder.DocumentIDs, docID)
	folder.UpdatedAt = time.Now().Unix()
	s.data.Folders[folderID] = folder
}

func (s *Store) detachDocumentFromFolder(folderID, docID string) {
	if folderID == "" {
		return
	}

	folder, ok := s.data.Folders[folderID]
	if !ok {
		return
	}

	updated := folder.DocumentIDs[:0]
	for _, existing := range folder.DocumentIDs {
		if existing != docID {
			updated = append(updated, existing)
		}
	}
	folder.DocumentIDs = updated
	folder.UpdatedAt = time.Now().Unix()
	s.data.Folders[folderID] = folder
}
