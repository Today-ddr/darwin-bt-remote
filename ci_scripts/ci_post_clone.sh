#!/usr/bin/env bash

which xcodegen || brew install xcodegen

cd "${CI_PRIMARY_REPOSITORY_PATH:-.}"
xcodegen generate
