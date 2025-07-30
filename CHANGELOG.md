# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.20.0] - 2025-07-29

### Changed
- **Repository Migration**: Republished `eventtracker-ios` under new name `arclight-event-tracker`
- **Pod Name**: Changed from `eventtracker-ios` to `arclight-event-tracker`
- **Version Bump**: Updated from previous version to 1.20.0

### Added
- **CI/CD Pipeline**: Added GitHub Actions workflow for automated testing and building
- **Automated Publishing**: Added automated CocoaPods publishing on tagged releases
- **Code Quality**: Integrated RuboCop for code style enforcement
- **Version Validation**: Added validation to ensure podspec version matches git tag
- **CocoaPods Caching**: Added caching for faster CI builds
- **Comprehensive Testing**: Added iOS simulator testing with proper code signing configuration

### Technical Improvements
- **iOS Deployment Target**: Updated minimum iOS version to 12.0
- **Build Configuration**: Optimized for CI/CD with proper simulator targeting
- **Documentation**: Added comprehensive release documentation and setup instructions
- **Workflow Automation**: Streamlined release process with automated validation

### Infrastructure
- **GitHub Actions**: 
  - CI workflow for build and test automation
  - Release workflow for automated CocoaPods publishing
  - Version validation and code quality checks
- **CocoaPods Integration**: Automated publishing to CocoaPods Trunk
- **Development Tools**: Added RuboCop for code style consistency

---

## Previous Versions

This project was previously published as `eventtracker-ios`. The migration to `arclight-event-tracker` represents a rebranding and modernization of the existing codebase with improved CI/CD infrastructure and automated release processes. 