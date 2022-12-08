name: "Bug report"
description: Create a report to help me to fix your issue
body:
- type: markdown
  attributes:
    value: |
		## Note ##
		raspiBackup is supported on RaspberryOS and Ubuntu as operating system and Raspberry HW only. There are environments out there which successfully run raspiBackup but any support requests or issues on unsupported environments will be rejected. 

- type: checkboxes
  id: Debug information
  attributes:
    label: Have you attached the debug log?
    description: You have to ;-)
    options:
      - label: yes
