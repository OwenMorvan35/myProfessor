package http

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

var allowedOrigins = []string{
	"http://localhost:5173",
	"http://localhost:8080",
}

func CORS() gin.HandlerFunc {
	config := cors.Config{
		AllowOrigins:     allowedOrigins,
		AllowOriginFunc:  func(origin string) bool { return true },
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Authorization", "Content-Type", "X-Requested-With"},
		AllowCredentials: true,
	}
	return cors.New(config)
}

func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		c.Next()

		duration := time.Since(start)
		log.Printf("%s %s %d %s", c.Request.Method, c.FullPath(), c.Writer.Status(), duration)
	}
}

func MaxBodySize(limit int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if limit > 0 {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, limit)
		}
		c.Next()
	}
}
