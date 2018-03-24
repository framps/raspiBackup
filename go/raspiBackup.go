package main

import (
	"fmt"

	"github.com/framps/raspiBackup/go/tools"
)

func main() {

	sourceDisk, _ := tools.NewDisk("sda")

	fmt.Println(sourceDisk)

}
