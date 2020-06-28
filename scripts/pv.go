package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"
)

// The spec has fields:
// Version:
// Release: 0

// telegraf-1.14.4-1.x86_64.rpm
// telegraf-1.14.0-0.rc1.x86_64.rpm
// telegraf-nightly.x86_64.rpm
// telegraf-1.15.0~d14b18f1-0.x86_64.rpm
//
// telegraf_1.14.4-1_amd64.deb
// telegraf_1.14.0~rc1-1_amd64.deb
// telegraf_nightly_amd64.deb
// telegraf_1.15.0~d14b18f1-0_amd64.deb
//
// telegraf-1.14.4_linux_amd64.tar.gz
// telegraf-1.14.0~rc1_linux_amd64.tar.gz
// telegraf-nightly_linux_amd64.tar.gz
// telegraf-1.15.0~d14b18f1_linux_amd64.tar.gz
//
// telegraf-1.14.4_windows_amd64.zip
// telegraf-1.14.0~rc1_windows_amd64.zip
// telegraf-nightly_windows_amd64.zip
// telegraf-1.15.0~d14b18f1_windows_amd64.zip

var (
	versionRe = regexp.MustCompile(`v([^\.]+\.[^\.]+\.[^-~]+)(?:(?:-(\w+))|(?:~(\w+)))?`)
)

type Version struct {
	version string
	rc      string
	hash    string
}

// telegraf-nightly.x86_64.rpm
//          ^     ^
//
// telegraf-1.14.4-1.x86_64.rpm
//          ^    ^
//
// telegraf-1.14.0-0.rc1.x86_64.rpm
//          ^    ^
//
// telegraf-1.15.0~d14b18f1-0.x86_64.rpm
//          ^    ^
func (v *Version) RPMVersion() string {
	return v.version
}

// telegraf-nightly.x86_64.rpm -> 0
// telegraf-1.14.4-1.x86_64.rpm -> 1
// telegraf-1.14.0-0.rc1.x86_64.rpm -> 0
// telegraf-1.15.0~d14b18f1-0.x86_64.rpm -> 0
func (v *Version) RPMRelease() string {
	if v.version == "nightly" {
		return "0"
	}

	if v.rc == "" && v.hash == "" {
		return "1"
	}

	return "0"
}

// telegraf-nightly.x86_64.rpm
//          ^     ^
//
// telegraf-1.14.4-1.x86_64.rpm
//          ^      ^
//
// telegraf-1.14.0-0.rc1.x86_64.rpm
//          ^          ^
//
// telegraf-1.15.0~d14b18f1-0.x86_64.rpm
//          ^               ^
func (v *Version) RPMFullVersion() string {
	if v.version == "nightly" {
		return "nightly"
	}

	if v.rc != "" {
		return fmt.Sprintf("%s-%s.%s", v.RPMVersion(), v.RPMRelease(), v.rc)
	}

	if v.hash != "" {
		return fmt.Sprintf("%s~%s-%s", v.RPMVersion(), v.hash, v.RPMRelease())
	}

	return fmt.Sprintf("%s-%s", v.RPMVersion(), v.RPMRelease())
}

func (v *Version) DebVersion() string {
	if v.rc == "" && v.hash == "" {
		return v.version
	}

	return v.version + "~" + v.rc + v.hash
}

func (v *Version) DebRevision() string {
	if v.hash != "" || v.version == "nightly" {
		return "0"
	}
	return "1"
}

func (v *Version) DebFullVersion() string {
	if v.version == "nightly" {
		return v.version
	}
	return v.DebVersion() + "-" + v.DebRevision()
}

func (v *Version) ZipFullVersion() string {
	if v.version == "nightly" {
		return v.version
	}
	return v.DebVersion()
}

func (v *Version) TarFullVersion() string {
	if v.version == "nightly" {
		return v.version
	}
	return v.DebVersion()
}

func version(version string) (*Version, error) {
	if version == "nightly" {
		return &Version{
			version: version,
		}, nil
	}

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
		fmt.Printf("RPM_FULL_VERSION=%s\n", v.RPMFullVersion())
		fmt.Printf("DEB_VERSION=%s\n", v.DebVersion())
		fmt.Printf("DEB_REVISION=%s\n", v.DebRevision())
		fmt.Printf("DEB_FULL_VERSION=%s\n", v.DebFullVersion())
		fmt.Printf("ZIP_FULL_VERSION=%s\n", v.ZipFullVersion())
		fmt.Printf("TAR_FULL_VERSION=%s\n", v.TarFullVersion())
	}
}
