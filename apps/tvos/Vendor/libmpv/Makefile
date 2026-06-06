# bsogulcan/libmpv-darwin-build dylibs for tvOS + tvOS Simulator
# Source: https://github.com/bsogulcan/libmpv-darwin-build/releases/tag/v0.6.4

RELEASE   ?= v0.6.4
BASE_URL  ?= https://github.com/bsogulcan/libmpv-darwin-build/releases/download/$(RELEASE)
CACHE     := .cache/$(RELEASE)
DYLIBS    := Dylibs

# <target-dir>@<tar-basename>
SLICES := \
	appletvos/arm64@libmpv-libs_$(RELEASE)_tvos-arm64-video-default \
	appletvsimulator/arm64@libmpv-libs_$(RELEASE)_tvossimulator-arm64-video-default \
	appletvsimulator/x86_64@libmpv-libs_$(RELEASE)_tvossimulator-amd64-video-default

all: $(DYLIBS)/.stamp

$(DYLIBS)/.stamp:
	@mkdir -p $(CACHE) $(DYLIBS)
	@for spec in $(SLICES); do \
		dst=$${spec%@*}; src=$${spec#*@}; \
		archive=$(CACHE)/$${src}.tar.gz; \
		if [ ! -f $${archive} ]; then \
			echo "==> downloading $${src}.tar.gz"; \
			curl -fL --retry 3 --retry-delay 2 \
				-o $${archive}.tmp \
				$(BASE_URL)/$${src}.tar.gz; \
			mv $${archive}.tmp $${archive}; \
		fi; \
		echo "==> extracting $${dst}"; \
		rm -rf $(DYLIBS)/$${dst}; \
		mkdir -p $(DYLIBS)/$${dst}; \
		tar -xzf $${archive} -C $(DYLIBS)/$${dst} --strip-components 1; \
	done
	@touch $(DYLIBS)/.stamp

clean:
	rm -rf $(DYLIBS)

distclean: clean
	rm -rf .cache

.PHONY: all clean distclean
