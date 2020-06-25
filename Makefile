NEXT_VERSION := 1.15.0
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
COMMIT ?= $(shell git rev-parse --short HEAD)
LDFLAGS += -X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.branch=$(BRANCH)
PREFIX ?= /usr/local

ifeq ($(OS), Windows_NT)
	VERSION := $(shell git describe --exact-match --tags 2>nul)
	HOME := $(HOMEPATH)
	EXE := .exe
else ifeq ($(SHELL), sh.exe)
	VERSION := $(shell git describe --exact-match --tags 2>nul)
	HOME := $(HOMEPATH)
	CGO_ENABLED ?= 0
	export CGO_ENABLED
	EXE := .exe
else
	VERSION ?= $(shell git describe --exact-match --tags 2>/dev/null)
endif

ifeq ($(VERSION),)
	VERSION = $(NEXT_VERSION)
endif

ifdef TAG
	FULL_VERSION := $(VERSION)
else ifeq ($(VERSION), nightly)
	FULL_VERSION := $(VERSION)
else
	FULL_VERSION := $(VERSION)~$(COMMIT)
endif

GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
GOHOST := env -u GOOS -u GOARCH -u GOARM -- go

MAKEFLAGS += --no-print-directory

.PHONY: all
all:
	@$(MAKE) deps
	@$(MAKE) telegraf

.PHONY: help
help:
	@echo 'Targets:'
	@echo '  all        - download dependencies and compile telegraf binary'
	@echo '  deps       - download dependencies'
	@echo '  telegraf   - compile telegraf binary'
	@echo '  test       - run short unit tests'
	@echo '  fmt        - format source files'
	@echo '  tidy       - tidy go modules'
	@echo '  check-deps - check docs/LICENSE_OF_DEPENDENCIES.md'
	@echo '  clean      - delete build artifacts'
	@echo ''
	@echo 'Easy Package Targets:'
	@echo '  deb        - build a deb package'
	@echo '  rpm        - build a rpm package'
	@echo '  zip        - build a zip package'
	@echo '  tar.gz     - build a tar.gz package'
	@echo ''
	@echo 'Full Package Target List:'
	@$(foreach dist,$(dists),echo "  $(dist)";)

.PHONY: deps
deps:
	go mod download

telegraf:
	go build -ldflags "$(LDFLAGS)" ./cmd/telegraf

.PHONY: install
install:
	@if [ $(GOOS) != "windows" ]; then \
		mkdir -p "$(DESTDIR)" ; \
		mkdir -p "$(DESTDIR)$(PREFIX)/bin" ; \
		mkdir -p "$(DESTDIR)/etc/telegraf/telegraf.d" ; \
		mkdir -p "$(DESTDIR)/etc/logrotate.d" ; \
		mkdir -p "$(DESTDIR)/var/log/telegraf" ; \
		go build -o "$(DESTDIR)$(PREFIX)/bin" -ldflags "-w -s $(LDFLAGS)" ./cmd/telegraf ; \
		cp -f etc/telegraf.conf "$(DESTDIR)/etc/telegraf" ; \
		cp -f etc/logrotate.d/telegraf "$(DESTDIR)/etc/logrotate.d/telegraf" ; \
	else \
		mkdir -p "$(DESTDIR)" ; \
		go build -o "$(DESTDIR)" -ldflags "-w -s $(LDFLAGS)" ./cmd/telegraf ; \
		cp -f etc/telegraf_windows.conf $(DESTDIR)/telegraf.conf ; \
	fi

	@if  [ $(GOOS) == "linux" ]; then \
		mkdir -p "$(DESTDIR)$(PREFIX)/lib/telegraf/scripts" ; \
		cp -f scripts/init.sh $(DESTDIR)$(PREFIX)/lib/telegraf/scripts ; \
		cp -f scripts/telegraf.service $(DESTDIR)$(PREFIX)/lib/telegraf/scripts ; \
	fi

.PHONY: test
test:
	go test -short ./...

.PHONY: fmt
fmt:
	@gofmt -s -w $(filter-out plugins/parsers/influx/machine.go, $(shell git ls-files '*.go')))

.PHONY: fmtcheck
fmtcheck: GOFMT = $(shell gofmt -l $(filter-out plugins/parsers/influx/machine.go, $(shell git ls-files '*.go')))
fmtcheck:
	@if [ ! -z "$(GOFMT)" ]; then \
		echo "[ERROR] gofmt has found errors in the following files:"  ; \
		echo "$(GOFMT)" ; \
		echo "" ;\
		echo "Run 'make fmt' to fix them." ; \
		echo "" ;\
		exit 1 ;\
	fi

.PHONY: test-windows
test-windows:
	go test -short ./plugins/inputs/ping/...
	go test -short ./plugins/inputs/win_perf_counters/...
	go test -short ./plugins/inputs/win_services/...
	go test -short ./plugins/inputs/procstat/...
	go test -short ./plugins/inputs/ntpq/...
	go test -short ./plugins/processors/port_name/...

.PHONY: vet
vet:
	@echo 'go vet $$(go list ./... | grep -v ./plugins/parsers/influx)'
	@go vet $$(go list ./... | grep -v ./plugins/parsers/influx) ; if [ $$? -ne 0 ]; then \
		echo ""; \
		echo "go vet has found suspicious constructs. Please remediate any reported errors"; \
		echo "to fix them before submitting code for review."; \
		exit 1; \
	fi

.PHONY: tidy
tidy:
	go mod verify
	go mod tidy
	@if ! git diff --quiet go.mod go.sum; then \
		echo "please run go mod tidy and check in changes"; \
		exit 1; \
	fi

.PHONY: check
check: fmtcheck vet
	@$(MAKE) --no-print-directory tidy

.PHONY: test-all
test-all: fmtcheck vet
	go test ./...

.PHONY: check-deps
check-deps:
	./scripts/check-deps.sh

.PHONY: clean
clean:
	-rm -f telegraf
	-rm -f telegraf.exe
	-rm -rf build

plugins/parsers/influx/machine.go: plugins/parsers/influx/machine.go.rl
	ragel -Z -G2 $^ -o $@

.PHONY: plugin-%
plugin-%:
	@echo "Starting dev environment for $${$(@)} input plugin..."
	@docker-compose -f plugins/inputs/$${$(@)}/dev/docker-compose.yml up

deb_amd64 := amd64
deb_386 := i386
deb_s390x := s390x
deb_arm5 := armel
deb_arm6 := armhf
deb_arm647 := arm64
deb_arch := $(deb_$(GOARCH)$(GOARM))

rpm_amd64 := amd64
rpm_386 := i386
rpm_s390x := s390x
rpm_arm5 := armel
rpm_arm6 := armv6hl
rpm_arm647 := aarch64
rpm_arch := $(rpm_$(GOARCH)$(GOARM))

.PHONY: deb
deb:
	$(MAKE) telegraf_$(DEB_FULL_VERSION)_$(deb_arch).deb

.PHONY: rpm
rpm:
	$(MAKE) telegraf-$(RPM_FULL_VERSION).$(rpm_arch).rpm

.PHONY: zip
zip:
	$(MAKE) telegraf-$(FULL_VERSION)_$(GOOS)_$(deb_arch).zip

.PHONY: tar.gz
tar.gz:
	$(MAKE) telegraf-$(FULL_VERSION)_$(GOOS)_$(deb_arch).tar.gz

.PHONY: docker-image
docker-image: deb
	docker build -f scripts/dev.docker \
		--build-arg "package=telegraf_$(DEB_FULL_VERSION)_$(deb_arch).deb" \
		-t "telegraf-dev:$(COMMIT)" .

RPM_FULL_VERSION := $(shell $(GOHOST) run scripts/pv.go $(FULL_VERSION) RPM_FULL_VERSION)
DEB_FULL_VERSION := $(shell $(GOHOST) run scripts/pv.go $(FULL_VERSION) DEB_FULL_VERSION)

debs := telegraf_$(DEB_FULL_VERSION)_amd64.deb
debs += telegraf_$(DEB_FULL_VERSION)_arm64.deb
debs += telegraf_$(DEB_FULL_VERSION)_armel.deb
debs += telegraf_$(DEB_FULL_VERSION)_armhf.deb
debs += telegraf_$(DEB_FULL_VERSION)_i386.deb
debs += telegraf_$(DEB_FULL_VERSION)_mips.deb
debs += telegraf_$(DEB_FULL_VERSION)_mipsel.deb
debs += telegraf_$(DEB_FULL_VERSION)_s390x.deb

rpms += telegraf-$(RPM_FULL_VERSION).aarch64.rpm
rpms += telegraf-$(RPM_FULL_VERSION).armel.rpm
rpms += telegraf-$(RPM_FULL_VERSION).armv6hl.rpm
rpms += telegraf-$(RPM_FULL_VERSION).i386.rpm
rpms += telegraf-$(RPM_FULL_VERSION).s390x.rpm
rpms += telegraf-$(RPM_FULL_VERSION).x86_64.rpm

tars += telegraf-$(FULL_VERSION)_darwin_amd64.tar.gz
tars += telegraf-$(FULL_VERSION)_freebsd_amd64.tar.gz
tars += telegraf-$(FULL_VERSION)_freebsd_i386.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_amd64.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_arm64.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_armel.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_armhf.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_i386.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_mips.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_mipsel.tar.gz
tars += telegraf-$(FULL_VERSION)_linux_s390x.tar.gz
tars += telegraf-$(FULL_VERSION)_static_linux_amd64.tar.gz

zips += telegraf-$(FULL_VERSION)_windows_amd64.zip
zips += telegraf-$(FULL_VERSION)_windows_i386.zip

dists := $(debs) $(rpms) $(tars) $(zips)

.PHONY: packages
packages: $(dists)

$(rpms):
	$(MAKE) install
	mkdir -p build/dist
	fpm --force \
		--log error \
		--architecture $(rpm_arch) \
		--input-type dir \
		--output-type rpm \
		--vendor InfluxData \
		--url https://github.com/influxdata/telegraf \
		--license MIT \
		--maintainer support@influxdb.com \
		--config-files /etc/telegraf/telegraf.conf \
		--config-files /etc/logrotate.d/telegraf \
		--after-install scripts/rpm/post-install.sh \
		--before-install scripts/rpm/pre-install.sh \
		--after-remove scripts/rpm/post-remove.sh \
		--description "Plugin-driven server agent for reporting metrics into InfluxDB." \
		--depends coreutils \
		--depends shadow-utils \
		--rpm-posttrans scripts/rpm/post-install.sh \
		--name telegraf \
		--version $(VERSION) \
		--iteration $(shell $(GOHOST) -- go run scripts/pv.go $(FULL_VERSION) RPM_RELEASE) \
        --chdir $(DESTDIR) \
		--package build/dist/$@

$(debs):
	$(MAKE) install
	mkdir -p build/dist
	cp -f "$(DESTDIR)/etc/telegraf/telegraf.conf{,.sample}"
	fpm --force \
		--log error \
		--architecture $(deb_arch) \
		--input-type dir \
		--output-type deb \
		--vendor InfluxData \
		--url https://github.com/influxdata/telegraf \
		--license MIT \
		--maintainer support@influxdb.com \
		--config-files /etc/telegraf/telegraf.conf.sample \
		--config-files /etc/logrotate.d/telegraf \
		--after-install scripts/deb/post-install.sh \
		--before-install scripts/deb/pre-install.sh \
		--after-remove scripts/deb/post-remove.sh \
		--before-remove scripts/deb/pre-remove.sh \
		--description "Plugin-driven server agent for reporting metrics into InfluxDB." \
		--name telegraf \
		--version $(VERSION) \
		--iteration $(shell $(GOHOST) -- go run scripts/pv.go $(FULL_VERSION) DEB_REVISION) \
        --chdir $(DESTDIR) \
		--package build/dist/$@

.PHONY: $(zips)
$(zips):
	$(MAKE) install
	mkdir -p build/dist
	(cd $(dir $(DESTDIR)) && zip -r - ./*) > build/dist/$@

.PHONY: $(tars)
$(tars):
	$(MAKE) install
	tar --owner 0 --group 0 -czvf build/dist/$@ -C $(dir $(DESTDIR)) .

%amd64.deb %x86_64.rpm %linux_amd64.tar.gz: export GOOS := linux
%amd64.deb %x86_64.rpm %linux_amd64.tar.gz: export GOARCH := amd64

%static_linux_amd64.tar.gz: export cgo := -nocgo
%static_linux_amd64.tar.gz: export CGO_ENABLED := 0

%i386.deb %i386.rpm %linux_i386.tar.gz: export GOOS := linux
%i386.deb %i386.rpm %linux_i386.tar.gz: export GOARCH := 386

%armel.deb %armel.rpm %linux_armel.tar.gz: export GOOS := linux
%armel.deb %armel.rpm %linux_armel.tar.gz: export GOARCH := arm
%armel.deb %armel.rpm %linux_armel.tar.gz: export GOARM := 5

%armhf.deb %armv6hl.rpm %linux_armhf.tar.gz: export GOOS := linux
%armhf.deb %armv6hl.rpm %linux_armhf.tar.gz: export GOARCH := arm
%armhf.deb %armv6hl.rpm %linux_armhf.tar.gz: export GOARM := 6

%arm64.deb %aarch64.rpm %linux_arm64.tar.gz: export GOOS := linux
%arm64.deb %aarch64.rpm %linux_arm64.tar.gz: export GOARCH := arm64
%arm64.deb %aarch64.rpm %linux_arm64.tar.gz: export GOARM := 7

%s390x.deb %s390x.rpm %linux_s390x.tar.gz: export GOOS := linux
%s390x.deb %s390x.rpm %linux_s390x.tar.gz: export GOARCH := s390x

%freebsd_amd64.tar.gz: export GOOS := freebsd
%freebsd_amd64.tar.gz: export GOARCH := amd64

%freebsd_i386.tar.gz: export GOOS := freebsd
%freebsd_i386.tar.gz: export GOARCH := 386

%windows_amd64.zip: export EXE := .exe
%windows_amd64.zip: export GOOS := windows
%windows_amd64.zip: export GOARCH := amd64

%windows_i386.zip: export EXE := .exe
%windows_i386.zip: export GOOS := windows
%windows_i386.zip: export GOARCH := 386

%.deb %.rpm %.zip %.tar.gz: export PREFIX := /usr
%.deb %.rpm %.zip %.tar.gz: export DESTDIR = build/$(GOOS)/$(GOARCH)$(cgo)/telegraf-$(VERSION)
