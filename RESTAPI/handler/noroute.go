package handler

import "github.com/gin-gonic/gin"

// NoRouteHandler -
func NoRouteHandler(c *gin.Context) {
	c.JSON(404, gin.H{"code": "PAGE_NOT_FOUND", "message": "Page not found"})
}
