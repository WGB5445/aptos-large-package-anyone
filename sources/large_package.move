/// # Aptos Large Packages Framework
///
/// This module provides a framework for uploading large Move packages to the Aptos network, supporting both standard accounts and objects.
/// To publish a package, you must split your metadata and modules into multiple chunks and upload them sequentially using `stage_code_chunk`.
///
/// ## Usage
///
/// 1. **Stage Code Chunks**:
///     - Call `stage_code_chunk` with the appropriate metadata and code chunks.
///     - Ensure that `code_indices` are provided in order from `0` to `last_module_idx` without any gaps. If there are gaps, `assemble_module_code` will abort.
///
/// 2. **Publish or Upgrade**:
///     - To publish the staged package to an account, call `publish_staged_package`.
///     - To publish or upgrade the package to an object, call `publish_object_staged_package` or `upgrade_object_staged_package` with the required `code_object` argument.
///
/// 3. **Cleanup**:
///     - To remove the `StagingArea` resource from an account, call `cleanup_staging_area`.
///
/// ## Notes
///
/// - Ensure that the LargePackages module is deployed to your target network. It is available on mainnet and testnet at `0xa29df848eebfe5d981f708c2a5b06d31af2be53bbd8ddc94c8523f4b903f7adb`, and on devnet/localnet at `0x7` (aptos-experimental).
/// - The length of `code_indices` and `code_chunks` must match.
/// - Only the target address set in the staging area can publish or upgrade the package.
/// - For object code upgrades, you must provide a valid object reference.
module contract::large_packages {
    use std::error;
    use std::signer;
    use std::option::{Self, Option};
    use aptos_std::smart_table::{Self, SmartTable};

    use aptos_framework::code::{Self, PackageRegistry};
    use aptos_framework::object::{Object};
    use aptos_framework::object_code_deployment::{Self};

    /// code_indices and code_chunks should be the same length.
    const ECODE_MISMATCH: u64 = 1;
    /// Object reference should be provided when upgrading object code.
    const EMISSING_OBJECT_REFERENCE: u64 = 2;
    /// Target address must be set before publishing.
    const ETARGET_ADDRESS_NOT_SET: u64 = 3;
    /// Only the target address can publish the package.
    const EINVALID_PUBLISHER: u64 = 4;

    struct StagingArea has key {
        metadata_serialized: vector<u8>,
        code: SmartTable<u64, vector<u8>>,
        last_module_idx: u64,
        target_address: Option<address>,
    }

    public entry fun stage_code_chunk(
        owner: &signer,
        metadata_chunk: vector<u8>,
        code_indices: vector<u16>,
        code_chunks: vector<vector<u8>>,
        target_address: address, 
    ) acquires StagingArea {
        stage_code_chunk_internal(owner, metadata_chunk, code_indices, code_chunks, target_address);
    }

    public entry fun publish_staged_package(owner: &signer, chunk_owner: address) acquires StagingArea {
        let staging_area = &mut StagingArea[chunk_owner];
        publish_to_account(owner, staging_area);
        cleanup_staging_area_internal(*staging_area.target_address.borrow());
    }

    public entry fun publish_object_staged_package(owner: &signer, chunk_owner: address) acquires StagingArea {
        let staging_area = &mut StagingArea[chunk_owner];
        publish_to_object(owner, staging_area);
        cleanup_staging_area_internal(*staging_area.target_address.borrow());
    }

    public entry fun upgrade_object_staged_package(owner: &signer, chunk_owner: address ,code_object: Object<PackageRegistry>) acquires StagingArea {
        let staging_area = &mut StagingArea[chunk_owner];
        upgrade_object_code(owner, staging_area, code_object);
        cleanup_staging_area_internal(*staging_area.target_address.borrow());
    }

    public entry fun set_target_address(owner: &signer, new_target: address) acquires StagingArea {
        let staging_area = borrow_global_mut<StagingArea>(signer::address_of(owner));
        staging_area.target_address = option::some(new_target);
    }

    inline fun stage_code_chunk_internal(
        owner: &signer,
        metadata_chunk: vector<u8>,
        code_indices: vector<u16>,
        code_chunks: vector<vector<u8>>,
        target_address: address,
    ): &mut StagingArea acquires StagingArea {
        assert!(
            code_indices.length() == code_chunks.length(),
            error::invalid_argument(ECODE_MISMATCH),
        );

        let owner_address = signer::address_of(owner);

        if (!exists<StagingArea>(owner_address)) {
            move_to(owner, StagingArea {
                metadata_serialized: vector[],
                code: smart_table::new(),
                last_module_idx: 0,
                target_address: option::none(),
            });
        };

        let staging_area = borrow_global_mut<StagingArea>(owner_address);

        if (staging_area.target_address.is_none()) {
            staging_area.target_address = option::some(target_address);
        };

        if (!metadata_chunk.is_empty()) {
            staging_area.metadata_serialized.append(metadata_chunk);
        };

        let i = 0;
        while (i < code_chunks.length()) {
            let inner_code = *code_chunks.borrow(i);
            let idx = (*code_indices.borrow(i) as u64);

            if (staging_area.code.contains(idx)) {
                staging_area.code.borrow_mut(idx).append(inner_code);
            } else {
                staging_area.code.add(idx, inner_code);
                if (idx > staging_area.last_module_idx) {
                    staging_area.last_module_idx = idx;
                }
            };
            i += 1;
        };

        staging_area
    }

    inline fun check_publish_permissions(
        publisher: &signer,
        staging_area: &mut StagingArea,
    ) {
        assert!(
            staging_area.target_address.is_some(),
            error::invalid_argument(ETARGET_ADDRESS_NOT_SET),
        );

        assert!(
            &signer::address_of(publisher) == staging_area.target_address.borrow(),
            error::invalid_argument(EINVALID_PUBLISHER),
        );
    }

    inline fun publish_to_account(
        publisher: &signer,
        staging_area: &mut StagingArea,
    ) {
        check_publish_permissions(publisher, staging_area);
        let code = assemble_module_code(staging_area);
        code::publish_package_txn(publisher, staging_area.metadata_serialized, code);
    }

    inline fun publish_to_object(
        publisher: &signer,
        staging_area: &mut StagingArea,
    ) {
        check_publish_permissions(publisher, staging_area);
        let code = assemble_module_code(staging_area);
        object_code_deployment::publish(publisher, staging_area.metadata_serialized, code);
    }

    inline fun upgrade_object_code(
        publisher: &signer,
        staging_area: &mut StagingArea,
        code_object: Object<PackageRegistry>,
    ) {
        check_publish_permissions(publisher, staging_area);
        let code = assemble_module_code(staging_area);
        object_code_deployment::upgrade(publisher, staging_area.metadata_serialized, code, code_object);
    }

    inline fun assemble_module_code(
        staging_area: &mut StagingArea,
    ): vector<vector<u8>> {
        let last_module_idx = staging_area.last_module_idx;
        let code = vector[];
        let i = 0;
        while (i <= last_module_idx) {
            code.push_back(*staging_area.code.borrow(i));
            i += 1;
        };
        code
    }

    inline fun cleanup_staging_area_internal(chunk_owner: address) acquires StagingArea {
        let StagingArea {
            code,
            ..,
        } = StagingArea[chunk_owner];
        code.destroy();
    }

    public entry fun cleanup_staging_area(owner: &signer) acquires StagingArea {
        cleanup_staging_area_internal(signer::address_of(owner));
    }
}
