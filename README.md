# Large Packages Framework for Aptos

This Move package provides a framework for uploading and publishing large Move packages to the Aptos blockchain, supporting both standard accounts and objects. It is designed to handle large codebases by allowing package metadata and modules to be uploaded in multiple chunks.

## Features

- **Chunked Uploads:** Upload package metadata and module bytecode in multiple chunks.
- **Staging Area:** Temporarily store code chunks and metadata before publishing.
- **Flexible Publishing:** Publish or upgrade packages to accounts or objects.
- **Access Control:** Only the designated target address can publish or upgrade the package.
- **Cleanup:** Remove staging resources after publishing to free up storage.

## Usage

### 1. Stage Code Chunks

Use the `stage_code_chunk` entry function to upload chunks of metadata and module code.  
- Chunks must be uploaded in order, and `code_indices` should be sequential with no gaps.
- The `target_address` must be set to the intended publisher.

```move
public entry fun stage_code_chunk(
    owner: &signer,
    metadata_chunk: vector<u8>,
    code_indices: vector<u16>,
    code_chunks: vector<vector<u8>>,
    target_address: option::Option<address>
)
```

### 2. Publish or Upgrade

- **Publish to Account:**  
  Use `publish_staged_package` to publish the staged package to an account.

- **Publish to Object:**  
  Use `publish_object_staged_package` to publish to an object.

- **Upgrade Object Code:**  
  Use `upgrade_object_staged_package` to upgrade an existing object code package.

### 3. Cleanup

After publishing, use `cleanup_staging_area` to remove the staging resource and reclaim storage.

## Example Workflow

1. **Upload Chunks:**
   - Call `stage_code_chunk` multiple times to upload all metadata and module code chunks.

2. **Publish:**
   - Call `publish_staged_package` or `publish_object_staged_package` as needed.

## Notes

- The module uses `aptos_std::smart_table` for efficient storage of code chunks.
- Only the address specified in the staging area can publish or upgrade the package.
- The framework is compatible with both mainnet and testnet deployments.

## Directory Structure

```
sources/
  large_package.move      # Main Move module for large package management
Move.toml                # Package manifest
```

## License

MIT

---

For more details, see the code in [`sources/large_package.move`](sources/large_package.move ).
