swift package generate-grpc-code-from-protos --output-path Sources/Generated -- protos

swift package --allow-writing-to-package-directory generate-grpc-code-from-protos  --no-servers --access-level package --file-naming pathToUnderscores --output-path Sources/Generated -- protos
