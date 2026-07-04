.PHONY: binary artifactbundle release build test clean

EXECUTABLE   := asc-metadata-cli
BINARY_DIR   := binary
BINARY_PATH  := $(BINARY_DIR)/$(EXECUTABLE)

# リリースのバージョン。`make release VERSION=1.2.3` のように指定する
VERSION      ?= 0.0.0

BUNDLE_NAME  := $(EXECUTABLE).artifactbundle
BUNDLE_DIR   := $(BINARY_DIR)/$(BUNDLE_NAME)
BUNDLE_ZIP   := $(BINARY_DIR)/$(BUNDLE_NAME).zip
VARIANT_DIR  := $(EXECUTABLE)-$(VERSION)-macos

# arm64 / x86_64 の universal binary を release ビルドして $(BINARY_PATH) に配置する
binary:
	swift build -v -c release --product $(EXECUTABLE) 
  BIN=$$(find .build -path "*/release/asc-metadata-cli" | head -1)
	test -n "$$BIN"
	cp "$$BIN" $(BINARY_PATH)

# SwiftPM の .binaryTarget から参照できる artifactbundle を作成する
artifactbundle: binary
	rm -rf $(BUNDLE_DIR)
	mkdir -p $(BUNDLE_DIR)/$(VARIANT_DIR)/bin
	cp -f $(BINARY_PATH) $(BUNDLE_DIR)/$(VARIANT_DIR)/bin/$(EXECUTABLE)
	@printf '%s\n' \
	  '{' \
	  '  "schemaVersion": "1.0",' \
	  '  "artifacts": {' \
	  '    "$(EXECUTABLE)": {' \
	  '      "type": "executable",' \
	  '      "version": "$(VERSION)",' \
	  '      "variants": [' \
	  '        {' \
	  '          "path": "$(VARIANT_DIR)/bin/$(EXECUTABLE)",' \
	  '          "supportedTriples": ["arm64-apple-macosx", "x86_64-apple-macosx"]' \
	  '        }' \
	  '      ]' \
	  '    }' \
	  '  }' \
	  '}' > $(BUNDLE_DIR)/info.json

# artifactbundle を zip 化し、binaryTarget 用の checksum を出力する
release: artifactbundle
	cd $(BINARY_DIR) && rm -f $(BUNDLE_NAME).zip && zip -r -y -q $(BUNDLE_NAME).zip $(BUNDLE_NAME)
	swift package compute-checksum $(BUNDLE_ZIP) | tee $(BUNDLE_ZIP).checksum

build:
	swift build

test:
	swift test

clean:
	swift package clean
	rm -rf $(BINARY_DIR)
