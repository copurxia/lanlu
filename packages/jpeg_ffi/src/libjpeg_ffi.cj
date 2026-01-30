package jpeg_ffi

// Minimal libjpeg bindings sufficient for decoding JPEG from memory.
//
// This targets libjpeg-turbo with JPEG_LIB_VERSION=80 (as on common distros).
// If you need broader compatibility, we can add conditional layout checks.

public const JPEG_LIB_VERSION: Int32 = 80

public const DCTSIZE2: Int64 = 64
public const NUM_QUANT_TBLS: Int64 = 4
public const NUM_HUFF_TBLS: Int64 = 4
public const NUM_ARITH_TBLS: Int64 = 16
public const MAX_COMPS_IN_SCAN: Int64 = 4
public const D_MAX_BLOCKS_IN_MCU: Int64 = 10

public type boolean = Int32
public type JDIMENSION = UInt32
public type JOCTET = UInt8
public type JSAMPLE = UInt8
public type JSAMPROW = CPointer<JSAMPLE>
public type JSAMPARRAY = CPointer<JSAMPROW>

public type J_COLOR_SPACE = Int32
public const JCS_UNKNOWN: J_COLOR_SPACE = 0
public const JCS_GRAYSCALE: J_COLOR_SPACE = 1
public const JCS_RGB: J_COLOR_SPACE = 2

public type J_DCT_METHOD = Int32
public type J_DITHER_MODE = Int32

@C
public struct jpeg_saved_marker_struct {
    init() { throw Exception("type should not be inited") }
}
public type jpeg_saved_marker_ptr = CPointer<jpeg_saved_marker_struct>

@C public struct jpeg_memory_mgr { init() { throw Exception("type should not be inited") } }
@C public struct jpeg_progress_mgr { init() { throw Exception("type should not be inited") } }
@C public struct jpeg_source_mgr { init() { throw Exception("type should not be inited") } }
@C public struct jpeg_component_info { init() { throw Exception("type should not be inited") } }
@C public struct JQUANT_TBL { init() { throw Exception("type should not be inited") } }
@C public struct JHUFF_TBL { init() { throw Exception("type should not be inited") } }

// setjmp/longjmp (glibc): used to catch libjpeg fatal errors safely.
@C
public struct __jmp_buf_tag {
    public let __jmpbuf: VArray<Int64, $8>
    public let __mask_was_saved: Int32
    public let __pad: Int32
    public let __saved_mask: VArray<UInt64, $16>

    public init(
        __jmpbuf: VArray<Int64, $8>,
        __mask_was_saved: Int32,
        __pad: Int32,
        __saved_mask: VArray<UInt64, $16>
    ) {
        this.__jmpbuf = __jmpbuf
        this.__mask_was_saved = __mask_was_saved
        this.__pad = __pad
        this.__saved_mask = __saved_mask
    }
}

foreign func __sigsetjmp(env: CPointer<__jmp_buf_tag>, savemask: Int32): Int32
foreign func __siglongjmp(env: CPointer<__jmp_buf_tag>, val: Int32): Unit

@C
public struct jpeg_common_struct {
    public var err: CPointer<jpeg_error_mgr>
    public var mem: CPointer<jpeg_memory_mgr>
    public var progress: CPointer<jpeg_progress_mgr>
    public var client_data: CPointer<Unit>
    public var is_decompressor: boolean
    public var global_state: Int32

    public init() {
        this.err = CPointer<jpeg_error_mgr>()
        this.mem = CPointer<jpeg_memory_mgr>()
        this.progress = CPointer<jpeg_progress_mgr>()
        this.client_data = CPointer<Unit>()
        this.is_decompressor = 0
        this.global_state = 0
    }
}

public type j_common_ptr = CPointer<jpeg_common_struct>

public type jpeg_error_exit_fn = CFunc<(cinfo: j_common_ptr) -> Unit>
public type jpeg_emit_message_fn = CFunc<(cinfo: j_common_ptr, msg_level: Int32) -> Unit>
public type jpeg_output_message_fn = CFunc<(cinfo: j_common_ptr) -> Unit>
public type jpeg_format_message_fn = CFunc<(cinfo: j_common_ptr, buffer: CString) -> Unit>
public type jpeg_reset_error_mgr_fn = CFunc<(cinfo: j_common_ptr) -> Unit>

@C
public struct jpeg_error_mgr {
    public var error_exit: jpeg_error_exit_fn
    public var emit_message: jpeg_emit_message_fn
    public var output_message: jpeg_output_message_fn
    public var format_message: jpeg_format_message_fn
    public var reset_error_mgr: jpeg_reset_error_mgr_fn

    public var msg_code: Int32
    // Union { int i[8]; char s[80]; } => 80 bytes aligned as int.
    public var msg_parm: VArray<Int32, $20>

    public var trace_level: Int32
    public var num_warnings: Int64

    // const char * const *  (treated as pointer-sized opaque)
    public var jpeg_message_table: CPointer<CString>
    public var last_jpeg_message: Int32
    public var addon_message_table: CPointer<CString>
    public var first_addon_message: Int32
    public var last_addon_message: Int32

    public init() {
        // Filled by jpeg_std_error; we still need a zero-init for safety.
        this.error_exit = jpeg_error_exit_fn(CPointer<Unit>())
        this.emit_message = jpeg_emit_message_fn(CPointer<Unit>())
        this.output_message = jpeg_output_message_fn(CPointer<Unit>())
        this.format_message = jpeg_format_message_fn(CPointer<Unit>())
        this.reset_error_mgr = jpeg_reset_error_mgr_fn(CPointer<Unit>())
        this.msg_code = 0
        this.msg_parm = VArray<Int32, $20>(repeat: 0)
        this.trace_level = 0
        this.num_warnings = 0
        this.jpeg_message_table = CPointer<CString>()
        this.last_jpeg_message = 0
        this.addon_message_table = CPointer<CString>()
        this.first_addon_message = 0
        this.last_addon_message = 0
    }
}

@C
public struct jpeg_decompress_struct {
    // jpeg_common_fields
    public var err: CPointer<jpeg_error_mgr>
    public var mem: CPointer<jpeg_memory_mgr>
    public var progress: CPointer<jpeg_progress_mgr>
    public var client_data: CPointer<Unit>
    public var is_decompressor: boolean
    public var global_state: Int32

    public var src: CPointer<jpeg_source_mgr>

    public var image_width: JDIMENSION
    public var image_height: JDIMENSION
    public var num_components: Int32
    public var jpeg_color_space: J_COLOR_SPACE

    public var out_color_space: J_COLOR_SPACE
    public var scale_num: UInt32
    public var scale_denom: UInt32
    public var output_gamma: Float64

    public var buffered_image: boolean
    public var raw_data_out: boolean

    public var dct_method: J_DCT_METHOD
    public var do_fancy_upsampling: boolean
    public var do_block_smoothing: boolean

    public var quantize_colors: boolean
    public var dither_mode: J_DITHER_MODE
    public var two_pass_quantize: boolean
    public var desired_number_of_colors: Int32
    public var enable_1pass_quant: boolean
    public var enable_external_quant: boolean
    public var enable_2pass_quant: boolean

    public var output_width: JDIMENSION
    public var output_height: JDIMENSION
    public var out_color_components: Int32
    public var output_components: Int32
    public var rec_outbuf_height: Int32

    public var actual_number_of_colors: Int32
    public var colormap: JSAMPARRAY

    public var output_scanline: JDIMENSION

    public var input_scan_number: Int32
    public var input_iMCU_row: JDIMENSION

    public var output_scan_number: Int32
    public var output_iMCU_row: JDIMENSION

    public var coef_bits: CPointer<VArray<Int32, $64>>

    public var quant_tbl_ptrs: VArray<CPointer<JQUANT_TBL>, $4>
    public var dc_huff_tbl_ptrs: VArray<CPointer<JHUFF_TBL>, $4>
    public var ac_huff_tbl_ptrs: VArray<CPointer<JHUFF_TBL>, $4>

    public var data_precision: Int32
    public var comp_info: CPointer<jpeg_component_info>

    public var is_baseline: boolean
    public var progressive_mode: boolean
    public var arith_code: boolean

    public var arith_dc_L: VArray<UInt8, $16>
    public var arith_dc_U: VArray<UInt8, $16>
    public var arith_ac_K: VArray<UInt8, $16>

    public var restart_interval: UInt32

    public var saw_JFIF_marker: boolean
    public var JFIF_major_version: UInt8
    public var JFIF_minor_version: UInt8
    public var density_unit: UInt8
    public var X_density: UInt16
    public var Y_density: UInt16
    public var saw_Adobe_marker: boolean
    public var Adobe_transform: UInt8

    public var CCIR601_sampling: boolean
    public var marker_list: jpeg_saved_marker_ptr

    public var max_h_samp_factor: Int32
    public var max_v_samp_factor: Int32

    public var min_DCT_h_scaled_size: Int32
    public var min_DCT_v_scaled_size: Int32

    public var total_iMCU_rows: JDIMENSION
    public var sample_range_limit: CPointer<JSAMPLE>

    public var comps_in_scan: Int32
    public var cur_comp_info: VArray<CPointer<jpeg_component_info>, $4>

    public var MCUs_per_row: JDIMENSION
    public var MCU_rows_in_scan: JDIMENSION

    public var blocks_in_MCU: Int32
    public var MCU_membership: VArray<Int32, $10>

    public var Ss: Int32
    public var Se: Int32
    public var Ah: Int32
    public var Al: Int32

    public var block_size: Int32
    public var natural_order: CPointer<Int32>
    public var lim_Se: Int32

    public var unread_marker: Int32

    // Links to decompression subobjects (opaque pointers for layout correctness)
    public var master: CPointer<Unit>
    public var mainCtrl: CPointer<Unit>
    public var coef: CPointer<Unit>
    public var post: CPointer<Unit>
    public var inputctl: CPointer<Unit>
    public var marker: CPointer<Unit>
    public var entropy: CPointer<Unit>
    public var idct: CPointer<Unit>
    public var upsample: CPointer<Unit>
    public var cconvert: CPointer<Unit>
    public var cquantize: CPointer<Unit>

    public init() {
        this.err = CPointer<jpeg_error_mgr>()
        this.mem = CPointer<jpeg_memory_mgr>()
        this.progress = CPointer<jpeg_progress_mgr>()
        this.client_data = CPointer<Unit>()
        this.is_decompressor = 0
        this.global_state = 0
        this.src = CPointer<jpeg_source_mgr>()

        this.image_width = 0u32
        this.image_height = 0u32
        this.num_components = 0
        this.jpeg_color_space = JCS_UNKNOWN

        this.out_color_space = JCS_RGB
        this.scale_num = 1u32
        this.scale_denom = 1u32
        this.output_gamma = 0.0

        this.buffered_image = 0
        this.raw_data_out = 0

        this.dct_method = 0
        this.do_fancy_upsampling = 1
        this.do_block_smoothing = 1

        this.quantize_colors = 0
        this.dither_mode = 0
        this.two_pass_quantize = 0
        this.desired_number_of_colors = 0
        this.enable_1pass_quant = 0
        this.enable_external_quant = 0
        this.enable_2pass_quant = 0

        this.output_width = 0u32
        this.output_height = 0u32
        this.out_color_components = 0
        this.output_components = 0
        this.rec_outbuf_height = 0

        this.actual_number_of_colors = 0
        this.colormap = CPointer<JSAMPROW>()

        this.output_scanline = 0u32

        this.input_scan_number = 0
        this.input_iMCU_row = 0u32
        this.output_scan_number = 0
        this.output_iMCU_row = 0u32

        this.coef_bits = CPointer<VArray<Int32, $64>>()

        this.quant_tbl_ptrs = VArray<CPointer<JQUANT_TBL>, $4>(repeat: CPointer<JQUANT_TBL>())
        this.dc_huff_tbl_ptrs = VArray<CPointer<JHUFF_TBL>, $4>(repeat: CPointer<JHUFF_TBL>())
        this.ac_huff_tbl_ptrs = VArray<CPointer<JHUFF_TBL>, $4>(repeat: CPointer<JHUFF_TBL>())

        this.data_precision = 0
        this.comp_info = CPointer<jpeg_component_info>()

        this.is_baseline = 0
        this.progressive_mode = 0
        this.arith_code = 0

        this.arith_dc_L = VArray<UInt8, $16>(repeat: 0u8)
        this.arith_dc_U = VArray<UInt8, $16>(repeat: 0u8)
        this.arith_ac_K = VArray<UInt8, $16>(repeat: 0u8)

        this.restart_interval = 0u32

        this.saw_JFIF_marker = 0
        this.JFIF_major_version = 0u8
        this.JFIF_minor_version = 0u8
        this.density_unit = 0u8
        this.X_density = 0u16
        this.Y_density = 0u16
        this.saw_Adobe_marker = 0
        this.Adobe_transform = 0u8

        this.CCIR601_sampling = 0
        this.marker_list = jpeg_saved_marker_ptr()

        this.max_h_samp_factor = 0
        this.max_v_samp_factor = 0
        this.min_DCT_h_scaled_size = 0
        this.min_DCT_v_scaled_size = 0

        this.total_iMCU_rows = 0u32
        this.sample_range_limit = CPointer<JSAMPLE>()

        this.comps_in_scan = 0
        this.cur_comp_info = VArray<CPointer<jpeg_component_info>, $4>(repeat: CPointer<jpeg_component_info>())

        this.MCUs_per_row = 0u32
        this.MCU_rows_in_scan = 0u32

        this.blocks_in_MCU = 0
        this.MCU_membership = VArray<Int32, $10>(repeat: 0)

        this.Ss = 0
        this.Se = 0
        this.Ah = 0
        this.Al = 0

        this.block_size = 0
        this.natural_order = CPointer<Int32>()
        this.lim_Se = 0

        this.unread_marker = 0

        this.master = CPointer<Unit>()
        this.mainCtrl = CPointer<Unit>()
        this.coef = CPointer<Unit>()
        this.post = CPointer<Unit>()
        this.inputctl = CPointer<Unit>()
        this.marker = CPointer<Unit>()
        this.entropy = CPointer<Unit>()
        this.idct = CPointer<Unit>()
        this.upsample = CPointer<Unit>()
        this.cconvert = CPointer<Unit>()
        this.cquantize = CPointer<Unit>()
    }
}

foreign func jpeg_std_error(err: CPointer<jpeg_error_mgr>): CPointer<jpeg_error_mgr>

foreign func jpeg_CreateDecompress(cinfo: CPointer<jpeg_decompress_struct>, version: Int32, structsize: UIntNative): Unit
foreign func jpeg_destroy_decompress(cinfo: CPointer<jpeg_decompress_struct>): Unit

foreign func jpeg_mem_src(cinfo: CPointer<jpeg_decompress_struct>, inbuffer: CString, insize: UInt64): Unit

foreign func jpeg_read_header(cinfo: CPointer<jpeg_decompress_struct>, require_image: Int32): Int32
foreign func jpeg_start_decompress(cinfo: CPointer<jpeg_decompress_struct>): Int32
foreign func jpeg_read_scanlines(cinfo: CPointer<jpeg_decompress_struct>, scanlines: JSAMPARRAY, max_lines: UInt32): UInt32
foreign func jpeg_finish_decompress(cinfo: CPointer<jpeg_decompress_struct>): Int32
