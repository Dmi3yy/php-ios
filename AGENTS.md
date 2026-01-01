# Repository Guidelines

## Project Structure & Module Organization
- `Sources/PhpIOS/` public Swift API (`PhpEngine`), resources (`Resources/php.ini`), and bundled static lib in `lib/` (excluded in target).
- `Sources/PhpIOSBridge/` Obj-C++ bridge (`PhpBridge.mm`) that calls into the embedded PHP runtime.
- `Tests/PhpIOSTests/` XCTest suite for `PhpEngine`.
- `SampleApp/` minimal SwiftPM app; PHP scripts live under `SampleApp/Sources/SampleApp/PhpScripts/`.
- `Toolchain/` cross-compile scripts and patches to rebuild `libphp-ios.a`.

## Build, Test, and Development Commands
Use Makefile targets (they wrap SwiftPM commands):
- `make build` - build the Swift package (`swift build`).
- `make test` - run XCTest (`swift test`).
- `make sample-app` - build the sample app from `SampleApp/`.
- `make build-php` - rebuild the static PHP runtime in `Toolchain/`.
- `make format` / `make lint` - run `swift-format` over `Sources/`, `Tests/`, `SampleApp/`.

## Coding Style & Naming Conventions
- Swift formatting is enforced with `swift-format`; run `make format` before committing.
- Use Swift naming conventions (UpperCamelCase for types, lowerCamelCase for methods/properties).
- Test methods follow `test...` naming in `*Tests.swift`.

## Testing Guidelines
- Tests use XCTest and live in `Tests/PhpIOSTests/`.
- Add coverage for new `PhpEngine` behaviors (stdout/stderr handling, stdin inputs).
- Run `make test` locally; no explicit coverage threshold is enforced.

## Commit & Pull Request Guidelines
- Commit messages are short and sentence case (e.g., "Initial commit", "Create README.md").
- PRs should include a concise summary, testing notes (commands + results), and linked issues.
- If you change `SampleApp/` UI or scripts, include a screenshot or example output.

## Security & App Store Constraints
- Only bundled `.php` scripts are allowed; do not add code download paths.
- Keep inputs treated as untrusted; prefer JSON IO and validate data in PHP and Swift.
