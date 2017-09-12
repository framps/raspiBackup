package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// IndexHandler -
func IndexHandler(c *gin.Context) {
	c.HTML(http.StatusOK, "index.html", nil)
}
