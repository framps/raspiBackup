package main

/*

 REST prototype for raspiBackup

 See https://www.linux-tips-and-tricks.de/en/backup for details about raspiBackup

 If there is any requirement for a full blown REST API please contact the author

 REST calls can be protected with userid and password. Just create a file /usr/local/etc/raspiBackup.auth
 and add lines in the format 'userid:password' to define access credetials.

 To invoke raspiBackup via REST use follwing command:
     curl -u userid:password -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar", "keep": 3}' http://<raspiHost>:8080/v1/raspiBackup

(c) 2017 - framp at linux-tips-and-tricks dot de

*/

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"

	"github.com/framps/raspiBackup/RESTAPI/handler"
	"github.com/framps/raspiBackup/RESTAPI/lib"
	"github.com/gin-gonic/gin"
)

func main() {

	gin.SetMode(gin.ReleaseMode)
	api := gin.Default()

	var passwordSet bool
	var credentialMap = map[string]string{}

	// read credentials
	if _, err := os.Stat(lib.PasswordFile); err == nil {
		fmt.Printf("INFO: Reading %v\n", lib.PasswordFile)
		credentials, err := ioutil.ReadFile(lib.PasswordFile)
		if err != nil {
			fmt.Printf("%+v", err)
			os.Exit(42)
		}

		f, err := os.Open(lib.PasswordFile)
		defer f.Close()
		if err != nil {
			log.Fatal(err)
		}

		fi, err := f.Stat()
		if err != nil {
			log.Fatal(err)
		}

		if mode := fi.Mode(); mode&077 != 0 {
			fmt.Printf("ERROR: %v not protected. %v\n", lib.PasswordFile, mode)
			os.Exit(42)
		}

		lines := strings.Split(string(credentials), "\n")

		for i, line := range lines {
			splitCredentials := strings.Split(string(line), ":")
			if len(splitCredentials) == 2 {
				uid, pwd := strings.TrimSpace(splitCredentials[0]), strings.TrimSpace(splitCredentials[1])
				credentialMap[uid] = pwd
				fmt.Printf("INFO: Line %d: Found credential definition for userid '%s'\n", i, uid)
				passwordSet = true
			} else {
				if len(line) > 0 {
					fmt.Printf("WARNING: Line %d skipped. Found '%s' which is not a valid credential definition. Expected 'userid:password'\n", i, line)
				}
			}
		}

	} else {
		fmt.Printf("WARNING: REST API not protected with basic auth. %s not found\n", lib.PasswordFile)
	}

	var v1 *gin.RouterGroup

	if passwordSet {
		v1 = api.Group("v1", gin.BasicAuth(credentialMap))
	} else {
		v1 = api.Group("v1")
	}

	api.LoadHTMLGlob("templates/*.html")
	api.NoRoute(handler.NoRouteHandler)

	v1.POST("/raspiBackup", handler.BackupHandler)
	v1.GET("/", handler.IndexHandler)

	api.Run(":8080")
}
