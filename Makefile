.PHONY: setup run build clean

PROJECT_DIR := $(CURDIR)
APP_DIR := $(PROJECT_DIR)/Parrocchettami

setup:
	bash $(PROJECT_DIR)/setup.sh

build:
	cd $(APP_DIR) && swift build

run:
	cd "$(APP_DIR)" && PARROCCHETTAMI_HOME="$(PROJECT_DIR)" swift run

clean:
	cd $(APP_DIR) && swift package clean
	rm -rf $(PROJECT_DIR)/bin $(PROJECT_DIR)/models
