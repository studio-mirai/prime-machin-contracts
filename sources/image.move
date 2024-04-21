module prime_machin::image {

    // === Imports ===

    use std::hash::{Self};
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use std::vector::{Self};

    use sui::display::{Self};
    use sui::dynamic_field::{Self};
    use sui::event;
    use sui::hex::{Self};
    use sui::object::{Self, ID, UID};
    use sui::package::{Self};
    use sui::transfer::{Self, Receiving};
    use sui::tx_context::{TxContext};
    use sui::vec_map::{Self, VecMap};
    use sui::vec_set::{Self, VecSet};
    
    // === Friends ===

    friend prime_machin::coloring;
    friend prime_machin::mint;
    friend prime_machin::factory;

    // === Errors ===

    const EImageChunkHashMismatch: u64 = 1;
    const EImageChunkMissingValue: u64 = 2;
    const EImageChunksNotDeleted: u64 = 3;
    const EImagePromiseMismatch: u64 = 4;
    const EWrongImageForChunk: u64 = 5;

    // === Structs ===

    struct IMAGE has drop {}

    struct CreateImageCap has key, store {
        id: UID,
        number: u16,
        level: u8,
        ref: ID,
    }

    struct CreateImageChunkCap has key {
        id: UID,
        number: u16,
        level: u8,
        index: u8,
        hash: String,
        image_id: ID,
    }

    struct DeleteImagePromise {
        image_id: ID,
    }

    struct Image has key, store {
        id: UID,
        number: u16,
        // Level of the image. 0 is black and white, 1 is color, 2 is custom.
        level: u8,
        // Data encoding scheme for frontend client to reconstruct image (Base85 for this collection).
        encoding: String,
        mime_type: String,
        extension: String,
        // Stores the ID of the CreateImageCap that was consumed.
        created_with: ID,
        // Stores a mapping between an image chunk's SHA-256 hash and its ID.
        chunks: VecMap<String, Option<ID>>,
    }

    struct ImageChunk has key {
        id: UID,
        // ID of the parent image.
        image_id: ID,
        number: u16,
        // SHA-256 hash of the image.
        hash: String,
        // Contextual context of the image chunk, needed to reconstruct the image.
        index: u8,
        // Base85-encoded string of the data.
        data: String,
    }

    struct RegisterImageChunkCap has key {
        id: UID,
        image_id: ID,
        chunk_id: ID,
        chunk_hash: String,
        // ID of the CreateImageChunkCap that was used to create this RegisterImageChunkCap.
        created_with: ID,
    }

    // === Events ===

    struct CreateImageCapCreatedEvent has copy, drop {
        id: ID,
        number: u16,
        level: u8,
    }

    struct CreateImageChunkCapCreatedEvent has copy, drop {
        id: ID,
        number: u16,
        level: u8,
        index: u8,
        hash: String,
        image_id: ID,
    }

    struct ImageCreatedEvent has copy, drop {
        id: ID,
        number: u16,
        level: u8,
    }

    struct ImageChunkCreatedEvent has copy, drop {
        id: ID,
        number: u16,
        hash: String,
        index: u8,
        image_id: ID,
    }

    // === Init Function ===

    #[allow(unused_variable, lint(share_owned))]
    fun init(
        otw: IMAGE,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);

        let image_chunk_display = display::new<ImageChunk>(&publisher, ctx);
        display::add(&mut image_chunk_display, string::utf8(b"name"), string::utf8(b"Prime Machin #{number} Image Chunk"));
        display::add(&mut image_chunk_display, string::utf8(b"description"), string::utf8(b"An image chunk for Prime Machin #{number}."));
        display::add(&mut image_chunk_display, string::utf8(b"image_url"), string::utf8(b"https://prime.nozomi.world/images/image_chunk_{level}_{number}_{index}.webp"));
        display::add(&mut image_chunk_display, string::utf8(b"image_id"), string::utf8(b"{image_id}"));
        display::add(&mut image_chunk_display, string::utf8(b"number"), string::utf8(b"{number}"));
        display::add(&mut image_chunk_display, string::utf8(b"hash"), string::utf8(b"{hash}"));
        display::add(&mut image_chunk_display, string::utf8(b"index"), string::utf8(b"{index}"));
        display::add(&mut image_chunk_display, string::utf8(b"data"), string::utf8(b"{data}"));

        transfer::public_transfer(publisher, @sm_treasury);
        transfer::public_transfer(image_chunk_display, @sm_treasury);
    }

    #[allow(lint(self_transfer))]
    public fun create_image(
        cap: CreateImageCap,
        image_chunk_hashes: vector<String>,
        ctx: &mut TxContext,
    ) {
        let image = Image {
            id: object::new(ctx),
            number: cap.number,
            level: cap.level,
            encoding: string::utf8(b"base85"),
            mime_type: string::utf8(b"image/avif"),
            extension: string::utf8(b"avif"),
            created_with: object::id(&cap),
            chunks: vec_map::empty(),
        };

        // let create_image_chunk_cap_ids = vector::empty<ID>();
        let create_image_chunk_cap_ids = vec_set::empty<ID>();

        // Initialize the chunks VecMap with expected chunk hashes as keys.
        while (!vector::is_empty(&image_chunk_hashes)) {
            let chunk_index = (vector::length(&image_chunk_hashes) as u8);
            let chunk_hash = vector::pop_back(&mut image_chunk_hashes);
            
            let create_image_chunk_cap = CreateImageChunkCap {
                id: object::new(ctx),
                number: cap.number,
                level: cap.level,
                index: chunk_index,
                hash: chunk_hash,
                image_id: object::id(&image),
            };

            event::emit(
                CreateImageChunkCapCreatedEvent {
                    id: object::id(&create_image_chunk_cap),
                    number: cap.number,
                    level: cap.level,
                    index: chunk_index,
                    hash: chunk_hash,
                    image_id: object::id(&image),
                }
            );

            vec_map::insert(&mut image.chunks, chunk_hash, option::none());
            vec_set::insert(&mut create_image_chunk_cap_ids, object::id(&create_image_chunk_cap));

            transfer::transfer(create_image_chunk_cap, @sm_api);
        };

        // Add a dynamic field to store the CreateImageChunkCap IDs.
        dynamic_field::add(
            &mut image.id,
            string::utf8(b"create_image_chunk_cap_ids"),
            create_image_chunk_cap_ids,
        );

        event::emit(
            ImageCreatedEvent {
                id: object::id(&image),
                number: cap.number,
                level: cap.level,
            }
        );

        let CreateImageCap { id, number: _, level: _, ref: _ } = cap;
        object::delete(id);

        transfer::transfer(image, @sm_api);
    }

    public fun create_and_transfer_image_chunk(
        cap: CreateImageChunkCap,
        data: vector<String>,
        ctx: &mut TxContext,
    ) {
        // Create an empty string.
        let concat_chunk_str = string::utf8(b"");
        
        // Loop through data, remove each string, and append it to the concatenated string.
        while (!vector::is_empty(&data)) {
            // Remove the first string in the vector.
            let chunk_str = vector::remove(&mut data, 0);
            string::append(&mut concat_chunk_str, chunk_str);
        };

        // Grab a reference to the concatenated string's underlying bytes.
        let concat_chunk_bytes = string::bytes(&concat_chunk_str);

        // Calculate a SHA-256 hash of the concatenated string.
        let chunk_hash_bytes = hash::sha2_256(*concat_chunk_bytes);
        let chunk_hash_hex = hex::encode(chunk_hash_bytes);
        let chunk_hash_str = string::utf8(chunk_hash_hex);

        // Assert the calculated hash matches the target hash.
        assert!(chunk_hash_str == cap.hash, EImageChunkHashMismatch);

        let chunk = ImageChunk {
            id: object::new(ctx),
            image_id: cap.image_id,
            number: cap.number,
            hash: chunk_hash_str,
            index: cap.index,
            data: concat_chunk_str,
        };

        let register_image_chunk_cap = RegisterImageChunkCap {
            id: object::new(ctx),
            image_id: cap.image_id,
            chunk_id: object::id(&chunk),
            chunk_hash: chunk_hash_str,
            created_with: object::id(&cap),
        };

        event::emit(
            ImageChunkCreatedEvent{
                id: object::id(&chunk),
                number: cap.number,
                hash: chunk_hash_str,
                index: cap.index,
                image_id: cap.image_id,
            }
        );

        // Transfer chunk to the image directly.
        transfer::transfer(chunk, object::id_to_address(&cap.image_id));
        transfer::transfer(register_image_chunk_cap, object::id_to_address(&cap.image_id));

        let CreateImageChunkCap {
            id,
            number: _,
            level: _,
            index: _,
            hash: _,
            image_id: _,
        } = cap;
        object::delete(id);
    }

    public(friend) fun issue_create_image_cap(
        number: u16,
        level: u8,
        ref: ID,
        ctx: &mut TxContext,
    ): CreateImageCap {
        let cap = CreateImageCap {
            id: object::new(ctx),
            number: number,
            level: level,
            ref: ref,
        };

        event::emit(
            CreateImageCapCreatedEvent {
                id: object::id(&cap),
                number: number,
                level: level,
            }
        );

        cap
    }

    public fun delete_image(
        image: Image,
        promise: DeleteImagePromise,
    ) {
        assert!(object::id(&image) == promise.image_id, EImagePromiseMismatch);
        assert!(vec_map::is_empty(&image.chunks), EImageChunksNotDeleted);

        let Image {
            id,
            number: _,
            level: _,
            encoding: _,
            mime_type: _,
            extension: _,
            created_with: _,
            chunks,
        } = image;

        // This will abort if the image chunks linked table is not empty.
        // We designed it this way to ensure there are no orphaned chunk objects
        // as a result of destroying the parent image object.
        vec_map::destroy_empty(chunks);
        object::delete(id);

        let DeleteImagePromise { image_id: _ } = promise;
    }

    public fun receive_and_register_image_chunk(
        image: &mut Image,
        cap_to_receive: Receiving<RegisterImageChunkCap>,
    ) {
        let cap = transfer::receive(&mut image.id, cap_to_receive);
        assert!(cap.image_id == object::id(image), EWrongImageForChunk);

        let chunk_opt = vec_map::get_mut(&mut image.chunks, &cap.chunk_hash);
        option::fill(chunk_opt, cap.chunk_id);

        // Borrow a mutable reference to the image's "create_image_chunk_cap_ids" dynamic field.
        let create_image_chunk_cap_ids_for_image_mut: &mut VecSet<ID> = dynamic_field::borrow_mut(&mut image.id, string::utf8(b"create_image_chunk_cap_ids"));
        // Remove the ID of the CreateImageChunkCap associated with the RegisterImageChunkCap in question.
        vec_set::remove(create_image_chunk_cap_ids_for_image_mut, &cap.created_with);

        // If the "create_image_chunk_cap_ids_for_image_mut" VecSet is empty,
        // remove the VecSet completely, unwrap it into keys vector, and destroy the empty vector.
        if (vec_set::is_empty(create_image_chunk_cap_ids_for_image_mut)) {
            let create_image_chunk_cap_ids_for_image: VecSet<ID> = dynamic_field::remove(&mut image.id, string::utf8(b"create_image_chunk_cap_ids"));
            let create_image_chunk_cap_ids_for_image_keys = vec_set::into_keys(create_image_chunk_cap_ids_for_image);
            vector::destroy_empty(create_image_chunk_cap_ids_for_image_keys);
        };

        let RegisterImageChunkCap {
            id,
            image_id: _,
            chunk_id: _,
            chunk_hash: _,
            created_with: _,
        } = cap;
        object::delete(id);
    }

    public fun receive_and_destroy_image_chunk(
        image: &mut Image,
        chunk_to_receive: Receiving<ImageChunk>,
    ) {
        let chunk = transfer::receive(&mut image.id, chunk_to_receive);

        let (_chunk_hash, chunk_opt) = vec_map::remove(&mut image.chunks, &chunk.hash);
        let _chunk_id = option::destroy_some(chunk_opt);

        let ImageChunk {
            id,
            image_id: _,
            number: _,
            hash: _,
            index: _,
            data: _,
        } = chunk;

        object::delete(id);
    }

    public(friend) fun issue_delete_image_promise(
        image: &Image,
    ): DeleteImagePromise {
        let promise = DeleteImagePromise {
            image_id: object::id(image),
        };

        promise
    }

    public(friend) fun verify_image_chunks_registered(
        image: &Image,
    ) {
        let chunk_keys = vec_map::keys(&image.chunks);

        while (!vector::is_empty(&chunk_keys)) {
            let chunk_key = vector::pop_back(&mut chunk_keys);
            let chunk_value = vec_map::get(&image.chunks, &chunk_key);
            assert!(option::is_some(chunk_value), EImageChunkMissingValue);
        };

        vector::destroy_empty(chunk_keys);
    }

    /// Return the ID of an Image.
    public(friend) fun id(
        image: &Image,
    ): ID {
        object::id(image)
    }

    /// Return the number of an Image.
    public(friend) fun number(
        image: &Image,
    ): u16 {
        image.number
    }

    /// Return the level of an Image.
    public(friend) fun level(
        image: &Image,
    ): u8 {
        image.level
    }

    /// Returns the ID of a CreateImageCap.
    public(friend) fun create_image_cap_id(
        cap: &CreateImageCap,
    ): ID {
        object::id(cap)
    }
}