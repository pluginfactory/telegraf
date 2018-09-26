NEXT_VERSION := 1.9.0
PREFIX ?= /usr/local
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
COMMIT ?= $(shell git rev-parse --short HEAD)
GOFILES ?= $(shell git ls-files '*.go')
GOFMT ?= $(shell gofmt -l $(filter-out plugins/parsers/influx/machine.go, $(GOFILES)))
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
LDFLAGS += -X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.branch=$(BRANCH)

ifeq ($(OS), Windows_NT)
	VERSION := $(shell git describe --exact-match --tags 2>nul)
	HOME := $(HOMEPATH)
else ifeq ($(SHELL), sh.exe)
	VERSION := $(shell git describe --exact-match --tags 2>nul)
	HOME := $(HOMEPATH)
	CGO_ENABLED ?= 0
	export CGO_ENABLED
else
	VERSION := $(shell git describe --exact-match --tags 2>/dev/null)
endif

ifndef VERSION
	VERSION := $(NEXT_VERSION)
endif

ifdef TAG
	FULL_VERSION := $(VERSION)
else
	FULL_VERSION := $(VERSION)~$(COMMIT)
endif

GONATIVE := env -u GOOS -u GOARCH -u GOARM
RPM_FULL_VERSION := $(shell $(GONATIVE) -- go run scripts/pv.go $(FULL_VERSION) RPM_FULL_VERSION)
DEB_FULL_VERSION := $(shell $(GONATIVE) -- go run scripts/pv.go $(FULL_VERSION) DEB_FULL_VERSION)

MAKEFLAGS += --no-print-directory

.PHONY: all
all:
	@$(MAKE) deps
	@$(MAKE) telegraf

.PHONY: help
help:
	@echo 'Targets:'
	@echo '  all      - download dependencies and compile telegraf binary'
	@echo '  deps     - download dependencies'
	@echo '  telegraf - compile telegraf binary'
	@echo '  test     - run unit tests'
	@echo '  install  - install to DESTDIR using PREFIX'
	 echo ''
	@echo 'Package Targets:'
	@echo '  deb      - build a deb package'
	@echo '  rpm      - build a rpm package'
	@echo '  zip      - build a zip package'
	@echo '  tar.gz   - build a tar.gz package'
	@echo '  package  - create all packages'
	@echo '  sign     - sign packages'
	 echo ''
	@echo 'Packages:'
	@$(foreach package,$(packages),echo "  $(package)";)

.PHONY: deps
deps:
	go mod download

.PHONY: telegraf
telegraf:
	go build -ldflags "$(LDFLAGS)" ./cmd/telegraf

.PHONY: install
install: telegraf etc/telegraf.conf etc/logrotate.d/telegraf
	if [ $(GOOS) != "windows" ]; then \
		mkdir -p $(DESTDIR)/etc/telegraf.d ; \
		mkdir -p $(DESTDIR)/var/log/telegraf ; \
		mkdir -p $(DESTDIR)/etc/logrotate.d ; \
		mkdir -p $(DESTDIR)/usr/lib/telegraf/scripts ; \
		mkdir -p $(DESTDIR)$(PREFIX)/bin/ ; \
		cp -f etc/telegraf.conf $(DESTDIR)/etc/telegraf ; \
		cp -f etc/logrotate.d/telegraf $(DESTDIR)/etc/logrotate.d ; \
		cp -f scripts/init.sh $(DESTDIR)/usr/lib/telegraf/scripts ; \
		cp -f scripts/telegraf.service $(DESTDIR)/usr/lib/telegraf/scripts ; \
		cp -f telegraf$(EXE) $(DESTDIR)$(PREFIX)/bin ; \
	else \
		mkdir -p $(DESTDIR) ; \
		cp -f etc/telegraf.conf $(DESTDIR)/telegraf ; \
		cp -f telegraf$(EXE) $(DESTDIR)/telegraf ; \
	fi

.PHONY: test
test:
	go test -short ./...

.PHONY: fmt
fmt:
	@gofmt -s -w $(filter-out plugins/parsers/influx/machine.go, $(GOFILES))

.PHONY: fmtcheck
fmtcheck:
	@if [ ! -z "$(GOFMT)" ]; then \
		echo "[ERROR] gofmt has found errors in the following files:"  ; \
		echo "$(GOFMT)" ; \
		echo "" ;\
		echo "Run make fmt to fix them." ; \
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

.PHONY: package
package:
	./scripts/build.py --package --platform=all --arch=all

.PHONY: package-release
package-release:
	./scripts/build.py --release --package --platform=all --arch=all \
		--upload --bucket=dl.influxdata.com/telegraf/releases

.PHONY: package-nightly
package-nightly:
	./scripts/build.py --nightly --package --platform=all --arch=all \
		--upload --bucket=dl.influxdata.com/telegraf/nightlies

.PHONY: clean
clean:
	rm -f telegraf
	rm -f telegraf.exe
	rm -rf build

.PHONY: docker-image
docker-image:
	docker build -f scripts/stretch.docker -t "telegraf:$(COMMIT)" .

plugins/parsers/influx/machine.go: plugins/parsers/influx/machine.go.rl
	ragel -Z -G2 $^ -o $@

.PHONY: static
static:
	@echo "Building static linux binary..."
	@CGO_ENABLED=0 \
	GOOS=linux \
	GOARCH=amd64 \
	go build -ldflags "$(LDFLAGS)" ./cmd/telegraf

.PHONY: plugin-%
plugin-%:
	@echo "Starting dev environment for $${$(@)} input plugin..."
	@docker-compose -f plugins/inputs/$${$(@)}/dev/docker-compose.yml up

.PHONY: ci-1.13
ci-1.13:
	docker build -t quay.io/influxdb/telegraf-ci:1.13.8 - < scripts/ci-1.13.docker
	docker push quay.io/influxdb/telegraf-ci:1.13.8

.PHONY: ci-1.12
ci-1.12:
	docker build -t quay.io/influxdb/telegraf-ci:1.12.17 - < scripts/ci-1.12.docker
	docker push quay.io/influxdb/telegraf-ci:1.12.17

plugins/parsers/influx/machine.go: plugins/parsers/influx/machine.go.rl
	ragel -Z -G2 $^ -o $@

rpm_amd64 = amd64
rpm_386 = i386
rpm_s390x = s390x
rpm_arm5 = armel
rpm_arm6 = armv6hl
rpm_arm647 = arm64

rpm_arch = $(rpm_$(GOARCH)$(GOARM))

deb_amd64 = amd64
deb_386 = i386
deb_s390x = s390x
deb_arm5 = armel
deb_arm6 = armhf
deb_arm647 = arm64

deb_arch = $(deb_$(GOARCH)$(GOARM))

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

.SECONDARY: %.deb %.rpm %.zip %.tar.gz
%.deb %.rpm %.zip %.tar.gz: export PREFIX = /usr
%.deb %.rpm %.zip %.tar.gz: export DESTDIR = build/$(GOOS)/$(deb_arch)
%.deb %.rpm %.zip %.tar.gz: export LDFLAGS = -w -s

%.rpm:
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
		--after-install scripts/post-install.sh \
		--before-install scripts/pre-install.sh \
		--after-remove scripts/post-remove.sh \
		--before-remove scripts/pre-remove.sh \
		--description "Plugin-driven server agent for reporting metrics into InfluxDB." \
		--depends coreutils \
		--depends shadow-utils \
		--rpm-posttrans scripts/post-install.sh \
		--name telegraf \
		--version $(VERSION) \
		--iteration $(shell $(GONATIVE) -- go run scripts/pv.go $(FULL_VERSION) RPM_RELEASE) \
        --chdir $(DESTDIR) \
		--package build/dist/$@

%.deb:
	$(MAKE) install
	mkdir -p build/dist
	fpm --force \
		--log error \
		--architecture $(rpm_arch) \
		--input-type dir \
		--output-type deb \
		--vendor InfluxData \
		--url https://github.com/influxdata/telegraf \
		--license MIT \
		--maintainer support@influxdb.com \
		--config-files /etc/telegraf/telegraf.conf \
		--config-files /etc/logrotate.d/telegraf \
		--after-install scripts/post-install.sh \
		--before-install scripts/pre-install.sh \
		--after-remove scripts/post-remove.sh \
		--before-remove scripts/pre-remove.sh \
		--description "Plugin-driven server agent for reporting metrics into InfluxDB." \
		--name telegraf \
		--version $(VERSION) \
		--iteration $(shell $(GONATIVE) -- go run scripts/pv.go $(FULL_VERSION) DEB_REVISION) \
        --chdir $(DESTDIR) \
		--package build/dist/$@

%.zip:
	@$(MAKE) install
	mkdir -p build/dist
	(cd $(DESTDIR) && zip -r - ./*) > build/dist/$@

%.tar.gz:
	$(MAKE) install
	mkdir -p build/dist
	tar --owner 0 --group 0 -czvf build/dist/$@ -C $(DESTDIR) .

packages := telegraf_$(DEB_FULL_VERSION)_amd64.deb
packages += telegraf_$(DEB_FULL_VERSION)_arm64.deb
packages += telegraf_$(DEB_FULL_VERSION)_armel.deb
packages += telegraf_$(DEB_FULL_VERSION)_armhf.deb
packages += telegraf_$(DEB_FULL_VERSION)_i386.deb
packages += telegraf_$(DEB_FULL_VERSION)_s390x.deb

packages += telegraf-$(RPM_FULL_VERSION).arm64.rpm
packages += telegraf-$(RPM_FULL_VERSION).armel.rpm
packages += telegraf-$(RPM_FULL_VERSION).armv6hl.rpm
packages += telegraf-$(RPM_FULL_VERSION).i386.rpm
packages += telegraf-$(RPM_FULL_VERSION).s390x.rpm
packages += telegraf-$(RPM_FULL_VERSION).x86_64.rpm

packages += telegraf-$(VERSION)_freebsd_amd64.tar.gz
packages += telegraf-$(VERSION)_freebsd_i386.tar.gz
packages += telegraf-$(VERSION)_linux_amd64.tar.gz
packages += telegraf-$(VERSION)_linux_arm64.tar.gz
packages += telegraf-$(VERSION)_linux_armel.tar.gz
packages += telegraf-$(VERSION)_linux_armhf.tar.gz
packages += telegraf-$(VERSION)_linux_i386.tar.gz
packages += telegraf-$(VERSION)_linux_s390x.tar.gz
packages += telegraf-$(VERSION)-static_linux_amd64.tar.gz

packages += telegraf-$(VERSION)_windows_amd64.zip
packages += telegraf-$(VERSION)_windows_i386.zip

package: $(packages)

%amd64.deb %x86_64.rpm %linux_amd64.tar.gz: export GOOS = linux
%amd64.deb %x86_64.rpm %linux_amd64.tar.gz: export GOARCH = amd64

%static_linux_amd64.tar.gz: export CGO_ENABLED = 0

%i386.deb %i386.rpm %linux_i386.tar.gz: export GOOS = linux
%i386.deb %i386.rpm %linux_i386.tar.gz: export GOARCH = 386

%armel.deb %armel.rpm %linux_armel.tar.gz: export GOOS = linux
%armel.deb %armel.rpm %linux_armel.tar.gz: export GOARCH = arm
%armel.deb %armel.rpm %linux_armel.tar.gz: export GOARM = 5

%armhf.deb %armv6hl.rpm %linux_armhf.tar.gz: export GOOS = linux
%armhf.deb %armv6hl.rpm %linux_armhf.tar.gz: export GOARCH = arm
%armhf.deb %armv6hl.rpm %linux_armhf.tar.gz: export GOARM = 6

%arm64.deb %arm64.rpm %linux_arm64.tar.gz: export GOOS = linux
%arm64.deb %arm64.rpm %linux_arm64.tar.gz: export GOARCH = arm64
%arm64.deb %arm64.rpm %linux_arm64.tar.gz: export GOARM = 7

%s390x.deb %s390x.rpm %linux_s390x.tar.gz: export GOOS = linux
%s390x.deb %s390x.rpm %linux_s390x.tar.gz: export GOARCH = s390x

%freebsd_amd64.tar.gz: export GOOS = freebsd
%freebsd_amd64.tar.gz: export GOARCH = amd64

%freebsd_i386.tar.gz: export GOOS = freebsd
%freebsd_i386.tar.gz: export GOARCH = 386

%windows_amd64.zip: export EXE = .exe
%windows_amd64.zip: export GOOS = windows
%windows_amd64.zip: export GOARCH = amd64

%windows_amd64.zip: export EXE = .exe
%windows_i386.zip: export GOOS = windows
%windows_i386.zip: export GOARCH = 386

sign: $(addsuffix .asc,$(packages))

.SECONDARY: %.asc
%.asc: %
	-rm -f $@
	gpg --armor --detach-sign $<
