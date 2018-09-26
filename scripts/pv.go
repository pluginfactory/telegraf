package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"
)

var (
	versionRe = regexp.MustCompile(`([^\.]+\.[^\.]+\.[^-~]+)(?:(?:-(\w+))|(?:~(\w+)))?`)
)

type Version struct {
	version string
	rc      string
	hash    string
}

func (v *Version) RPMVersion() string {
	return v.version
}

func (v *Version) RPMRelease() string {
	if v.rc == "" && v.hash == "" {
		return "1"
	}

	if v.rc != "" {
		num := strings.TrimPrefix(v.rc, "rc")
		return "0." + num
	}

	return "0"
}

func (v *Version) RPMExtraVer() string {
	if v.hash != "" {
		return v.hash
	}
	return v.rc
}

func (v *Version) RPMFullVersion() string {
	return v.RPMVersion() + "-" + v.RPMRelease() + "." + v.RPMExtraVer()
}

func (v *Version) DebVersion() string {
	if v.rc == "" && v.hash == "" {
		return v.version
	}

	return v.version + "~" + v.rc + v.hash
}

func (v *Version) DebRevision() string {
	if v.hash != "" {
		return "0"
	}
	return "1"
}

func (v *Version) DebFullVersion() string {
	return v.DebVersion() + "-" + v.DebRevision()
}

func version(version string) (*Version, error) {
	parts := versionRe.FindStringSubmatch(version)
	if parts == nil {
		return nil, fmt.Errorf("could not parse version: %s", version)
	}

	v := &Version{
		version: parts[1],
		rc:      parts[2],
		hash:    parts[3],
	}
	return v, nil
}

func main() {
	flag.Parse()
	args := flag.Args()
	if len(args) != 1 && len(args) != 2 {
		fmt.Printf("usage: pv <version> [variable]\n")
		os.Exit(1)
	}

	v, err := version(args[0])
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	var variable string
	if len(args) == 2 {
		variable = args[1]
	}

	switch variable {
	case "RPM_VERSION":
		fmt.Println(v.RPMVersion())
	case "RPM_RELEASE":
		fmt.Println(v.RPMRelease())
	case "RPM_EXTRAVER":
		fmt.Println(v.RPMExtraVer())
	case "RPM_FULL_VERSION":
		fmt.Println(v.RPMFullVersion())
	case "DEB_VERSION":
		fmt.Println(v.DebVersion())
	case "DEB_REVISION":
		fmt.Println(v.DebRevision())
	case "DEB_FULL_VERSION":
		fmt.Println(v.DebFullVersion())
	default:
		fmt.Printf("RPM_VERSION=%s\n", v.RPMVersion())
		fmt.Printf("RPM_RELEASE=%s\n", v.RPMRelease())
		fmt.Printf("RPM_EXTRAVER=%s\n", v.RPMExtraVer())
		fmt.Printf("RPM_FULL_VERSION=%s\n", v.RPMFullVersion())
		fmt.Printf("DEB_VERSION=%s\n", v.DebVersion())
		fmt.Printf("DEB_REVISION=%s\n", v.DebRevision())
		fmt.Printf("DEB_FULL_VERSION=%s\n", v.DebFullVersion())
	}
}
