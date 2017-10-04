package handler

import (
	"fmt"
	"net/http"
	"os/exec"
	"strconv"

	"github.com/framps/raspiBackup/RESTAPI/lib"
	"github.com/gin-gonic/gin"
)

type parameter struct {
	Target string  `json:"target" binding:"required"`
	Type   *string `json:"type,omitempty"`
	Keep   *int    `json:"keep,omitempty"`
}

// BackupHandler - handles requests for raspiBackup
func BackupHandler(c *gin.Context) {

	var parm parameter
	err := c.BindJSON(&parm)
	if err != nil {
		msg := fmt.Sprintf("%+v", err)
		c.JSON(http.StatusBadRequest, gin.H{"Invalid payload received": msg})
		return
	}

	var args string

	if parm.Type != nil {
		args = "-t " + *parm.Type
	}

	if parm.Keep != nil {
		args += "-k " + strconv.Itoa(*parm.Keep)
	}

	args += " " + parm.Target

	command := "sudo " + lib.Executable
	args = `"` + args + `"`
	combined := command + " " + args
	cmd := exec.Command("/bin/bash", "-c", combined)

	stdoutStderr, err := cmd.CombinedOutput()
	if err != nil {
		msg := fmt.Sprintf("%+v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": msg, "output": string(stdoutStderr[:])})
	}
}
