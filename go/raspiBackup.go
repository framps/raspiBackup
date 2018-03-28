package main

import (
	"github.com/framps/raspiBackup/go/artefacts"
	"github.com/framps/raspiBackup/go/commands"
)

func main() {

	sourceSystem := artefacts.NewSystem()
	targetDirectory := artefacts.NewBackupDirectory("/backup")
	commands.Backup(soureSystem, targetDirectory)

	targetSystem := artefacts.NewSystem("/dev/sda")
	sourceDirectory := artefacts.NewBackupDirectory("/backup/20180328-22:34:01")
	commands.Restore(sourceDirectory, targetSystem)

}
