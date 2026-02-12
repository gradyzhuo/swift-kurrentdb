swift package --allow-writing-to-package-directory \
      generate-grpc-code-from-protos \ 
        --no-servers \ # 不生成 server 的 code
        --access-level package \ # access-level 設定在 package
        --file-naming pathToUnderscores \ # 檔名包含路徑並且以_連接
        --output-path Sources/Generated \ # 輸出在 Sources/Generated 
        -- \
        proto/google/rpc \
        proto/kurrent/rpc \
        proto/kurrentdb/v1 \
        proto/kurrentdb/v2/registry \
        proto/kurrentdb/v2/streams
