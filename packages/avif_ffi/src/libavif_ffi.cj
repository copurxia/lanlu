// cjbind 0.2.7 生成，请勿编辑, DO NOT EDIT

package avif_ffi

public const AVIF_VERSION_MAJOR: Int64 = 1i64
public const AVIF_VERSION_MINOR: Int64 = 0i64
public const AVIF_VERSION_PATCH: Int64 = 4i64
public const AVIF_VERSION_DEVEL: Int64 = 0i64
public const AVIF_VERSION: Int64 = 1000400i64
public const AVIF_TRUE: Int64 = 1i64
public const AVIF_FALSE: Int64 = 0i64
public const AVIF_DIAGNOSTICS_ERROR_BUFFER_SIZE: Int64 = 256i64
public const AVIF_DEFAULT_IMAGE_SIZE_LIMIT: Int64 = 268435456i64
public const AVIF_DEFAULT_IMAGE_DIMENSION_LIMIT: Int64 = 32768i64
public const AVIF_DEFAULT_IMAGE_COUNT_LIMIT: Int64 = 2592000i64
public const AVIF_QUALITY_DEFAULT: Int64 = -1i64
public const AVIF_QUALITY_LOSSLESS: Int64 = 100i64
public const AVIF_QUALITY_WORST: Int64 = 0i64
public const AVIF_QUALITY_BEST: Int64 = 100i64
public const AVIF_QUANTIZER_LOSSLESS: Int64 = 0i64
public const AVIF_QUANTIZER_BEST_QUALITY: Int64 = 0i64
public const AVIF_QUANTIZER_WORST_QUALITY: Int64 = 63i64
public const AVIF_PLANE_COUNT_YUV: Int64 = 3i64
public const AVIF_SPEED_DEFAULT: Int64 = -1i64
public const AVIF_SPEED_SLOWEST: Int64 = 0i64
public const AVIF_SPEED_FASTEST: Int64 = 10i64
public const AVIF_REPETITION_COUNT_INFINITE: Int64 = -1i64
public const AVIF_REPETITION_COUNT_UNKNOWN: Int64 = -2i64
public const AVIF_MAX_AV1_LAYER_COUNT: Int64 = 4i64

public type avifBool = Int32

public const avifPlanesFlag_AVIF_PLANES_YUV: avifPlanesFlag = 1
public const avifPlanesFlag_AVIF_PLANES_A: avifPlanesFlag = 2
public const avifPlanesFlag_AVIF_PLANES_ALL: avifPlanesFlag = 255

public type avifPlanesFlag = UInt32

public type avifPlanesFlags = UInt32

public const avifChannelIndex_AVIF_CHAN_Y: avifChannelIndex = 0
public const avifChannelIndex_AVIF_CHAN_U: avifChannelIndex = 1
public const avifChannelIndex_AVIF_CHAN_V: avifChannelIndex = 2
public const avifChannelIndex_AVIF_CHAN_A: avifChannelIndex = 3

public type avifChannelIndex = UInt32

foreign func avifVersion(): CString

foreign func avifCodecVersions(outBuffer: CPointer<UInt8>): Unit

foreign func avifLibYUVVersion(): UInt32

foreign func avifAlloc(size: UIntNative): CPointer<Unit>

foreign func avifFree(p: CPointer<Unit>): Unit

public const avifResult_AVIF_RESULT_OK: avifResult = 0
public const avifResult_AVIF_RESULT_UNKNOWN_ERROR: avifResult = 1
public const avifResult_AVIF_RESULT_INVALID_FTYP: avifResult = 2
public const avifResult_AVIF_RESULT_NO_CONTENT: avifResult = 3
public const avifResult_AVIF_RESULT_NO_YUV_FORMAT_SELECTED: avifResult = 4
public const avifResult_AVIF_RESULT_REFORMAT_FAILED: avifResult = 5
public const avifResult_AVIF_RESULT_UNSUPPORTED_DEPTH: avifResult = 6
public const avifResult_AVIF_RESULT_ENCODE_COLOR_FAILED: avifResult = 7
public const avifResult_AVIF_RESULT_ENCODE_ALPHA_FAILED: avifResult = 8
public const avifResult_AVIF_RESULT_BMFF_PARSE_FAILED: avifResult = 9
public const avifResult_AVIF_RESULT_MISSING_IMAGE_ITEM: avifResult = 10
public const avifResult_AVIF_RESULT_DECODE_COLOR_FAILED: avifResult = 11
public const avifResult_AVIF_RESULT_DECODE_ALPHA_FAILED: avifResult = 12
public const avifResult_AVIF_RESULT_COLOR_ALPHA_SIZE_MISMATCH: avifResult = 13
public const avifResult_AVIF_RESULT_ISPE_SIZE_MISMATCH: avifResult = 14
public const avifResult_AVIF_RESULT_NO_CODEC_AVAILABLE: avifResult = 15
public const avifResult_AVIF_RESULT_NO_IMAGES_REMAINING: avifResult = 16
public const avifResult_AVIF_RESULT_INVALID_EXIF_PAYLOAD: avifResult = 17
public const avifResult_AVIF_RESULT_INVALID_IMAGE_GRID: avifResult = 18
public const avifResult_AVIF_RESULT_INVALID_CODEC_SPECIFIC_OPTION: avifResult = 19
public const avifResult_AVIF_RESULT_TRUNCATED_DATA: avifResult = 20
public const avifResult_AVIF_RESULT_IO_NOT_SET: avifResult = 21
public const avifResult_AVIF_RESULT_IO_ERROR: avifResult = 22
public const avifResult_AVIF_RESULT_WAITING_ON_IO: avifResult = 23
public const avifResult_AVIF_RESULT_INVALID_ARGUMENT: avifResult = 24
public const avifResult_AVIF_RESULT_NOT_IMPLEMENTED: avifResult = 25
public const avifResult_AVIF_RESULT_OUT_OF_MEMORY: avifResult = 26
public const avifResult_AVIF_RESULT_CANNOT_CHANGE_SETTING: avifResult = 27
public const avifResult_AVIF_RESULT_INCOMPATIBLE_IMAGE: avifResult = 28
public const avifResult_AVIF_RESULT_NO_AV1_ITEMS_FOUND: avifResult = 10

public type avifResult = UInt32

foreign func avifResultToString(result: avifResult): CString

@C
public struct avifROData {
    public let data: CString
    public let size: UIntNative

    public init(data: CString, size: UIntNative) {
        this.data = data
        this.size = size
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifROData>()
        if (size != 16) {
            throw Exception("Size of avifROData is not 16 but ${size} bytes")
        }
        let align = alignOf<avifROData>()
        if (align != 8) {
            throw Exception("Alignment of avifROData is not 8 but ${align} bytes")
        }
}

@C
public struct avifRWData {
    public let data: CString
    public let size: UIntNative

    public init(data: CString, size: UIntNative) {
        this.data = data
        this.size = size
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifRWData>()
        if (size != 16) {
            throw Exception("Size of avifRWData is not 16 but ${size} bytes")
        }
        let align = alignOf<avifRWData>()
        if (align != 8) {
            throw Exception("Alignment of avifRWData is not 8 but ${align} bytes")
        }
}

foreign func avifRWDataRealloc(raw: CPointer<avifRWData>, newSize: UIntNative): avifResult

foreign func avifRWDataSet(raw: CPointer<avifRWData>, data: CString, len: UIntNative): avifResult

foreign func avifRWDataFree(raw: CPointer<avifRWData>): Unit

foreign func avifGetExifTiffHeaderOffset(exif: CString, exifSize: UIntNative, offset: CPointer<UIntNative>): avifResult

foreign func avifGetExifOrientationOffset(exif: CString, exifSize: UIntNative, offset: CPointer<UIntNative>): avifResult

public const avifPixelFormat_AVIF_PIXEL_FORMAT_NONE: avifPixelFormat = 0
public const avifPixelFormat_AVIF_PIXEL_FORMAT_YUV444: avifPixelFormat = 1
public const avifPixelFormat_AVIF_PIXEL_FORMAT_YUV422: avifPixelFormat = 2
public const avifPixelFormat_AVIF_PIXEL_FORMAT_YUV420: avifPixelFormat = 3
public const avifPixelFormat_AVIF_PIXEL_FORMAT_YUV400: avifPixelFormat = 4
public const avifPixelFormat_AVIF_PIXEL_FORMAT_COUNT: avifPixelFormat = 5

public type avifPixelFormat = UInt32

foreign func avifPixelFormatToString(format: avifPixelFormat): CString

@C
public struct avifPixelFormatInfo {
    public let monochrome: avifBool
    public let chromaShiftX: Int32
    public let chromaShiftY: Int32

    public init(monochrome: avifBool, chromaShiftX: Int32, chromaShiftY: Int32) {
        this.monochrome = monochrome
        this.chromaShiftX = chromaShiftX
        this.chromaShiftY = chromaShiftY
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifPixelFormatInfo>()
        if (size != 12) {
            throw Exception("Size of avifPixelFormatInfo is not 12 but ${size} bytes")
        }
        let align = alignOf<avifPixelFormatInfo>()
        if (align != 4) {
            throw Exception("Alignment of avifPixelFormatInfo is not 4 but ${align} bytes")
        }
}

foreign func avifGetPixelFormatInfo(format: avifPixelFormat, info: CPointer<avifPixelFormatInfo>): Unit

public const avifChromaSamplePosition_AVIF_CHROMA_SAMPLE_POSITION_UNKNOWN: avifChromaSamplePosition = 0
public const avifChromaSamplePosition_AVIF_CHROMA_SAMPLE_POSITION_VERTICAL: avifChromaSamplePosition = 1
public const avifChromaSamplePosition_AVIF_CHROMA_SAMPLE_POSITION_COLOCATED: avifChromaSamplePosition = 2

public type avifChromaSamplePosition = UInt32

public const avifRange_AVIF_RANGE_LIMITED: avifRange = 0
public const avifRange_AVIF_RANGE_FULL: avifRange = 1

public type avifRange = UInt32

public const AVIF_COLOR_PRIMARIES_UNKNOWN: _cjbind_ty_1 = 0
public const AVIF_COLOR_PRIMARIES_BT709: _cjbind_ty_1 = 1
public const AVIF_COLOR_PRIMARIES_IEC61966_2_4: _cjbind_ty_1 = 1
public const AVIF_COLOR_PRIMARIES_UNSPECIFIED: _cjbind_ty_1 = 2
public const AVIF_COLOR_PRIMARIES_BT470M: _cjbind_ty_1 = 4
public const AVIF_COLOR_PRIMARIES_BT470BG: _cjbind_ty_1 = 5
public const AVIF_COLOR_PRIMARIES_BT601: _cjbind_ty_1 = 6
public const AVIF_COLOR_PRIMARIES_SMPTE240: _cjbind_ty_1 = 7
public const AVIF_COLOR_PRIMARIES_GENERIC_FILM: _cjbind_ty_1 = 8
public const AVIF_COLOR_PRIMARIES_BT2020: _cjbind_ty_1 = 9
public const AVIF_COLOR_PRIMARIES_XYZ: _cjbind_ty_1 = 10
public const AVIF_COLOR_PRIMARIES_SMPTE431: _cjbind_ty_1 = 11
public const AVIF_COLOR_PRIMARIES_SMPTE432: _cjbind_ty_1 = 12
public const AVIF_COLOR_PRIMARIES_EBU3213: _cjbind_ty_1 = 22

public type _cjbind_ty_1 = UInt32

public type avifColorPrimaries = UInt16

foreign func avifColorPrimariesGetValues(acp: avifColorPrimaries, outPrimaries: CPointer<Float32>): Unit

foreign func avifColorPrimariesFind(inPrimaries: CPointer<Float32>, outName: CPointer<CString>): avifColorPrimaries

public const AVIF_TRANSFER_CHARACTERISTICS_UNKNOWN: _cjbind_ty_2 = 0
public const AVIF_TRANSFER_CHARACTERISTICS_BT709: _cjbind_ty_2 = 1
public const AVIF_TRANSFER_CHARACTERISTICS_UNSPECIFIED: _cjbind_ty_2 = 2
public const AVIF_TRANSFER_CHARACTERISTICS_BT470M: _cjbind_ty_2 = 4
public const AVIF_TRANSFER_CHARACTERISTICS_BT470BG: _cjbind_ty_2 = 5
public const AVIF_TRANSFER_CHARACTERISTICS_BT601: _cjbind_ty_2 = 6
public const AVIF_TRANSFER_CHARACTERISTICS_SMPTE240: _cjbind_ty_2 = 7
public const AVIF_TRANSFER_CHARACTERISTICS_LINEAR: _cjbind_ty_2 = 8
public const AVIF_TRANSFER_CHARACTERISTICS_LOG100: _cjbind_ty_2 = 9
public const AVIF_TRANSFER_CHARACTERISTICS_LOG100_SQRT10: _cjbind_ty_2 = 10
public const AVIF_TRANSFER_CHARACTERISTICS_IEC61966: _cjbind_ty_2 = 11
public const AVIF_TRANSFER_CHARACTERISTICS_BT1361: _cjbind_ty_2 = 12
public const AVIF_TRANSFER_CHARACTERISTICS_SRGB: _cjbind_ty_2 = 13
public const AVIF_TRANSFER_CHARACTERISTICS_BT2020_10BIT: _cjbind_ty_2 = 14
public const AVIF_TRANSFER_CHARACTERISTICS_BT2020_12BIT: _cjbind_ty_2 = 15
public const AVIF_TRANSFER_CHARACTERISTICS_SMPTE2084: _cjbind_ty_2 = 16
public const AVIF_TRANSFER_CHARACTERISTICS_SMPTE428: _cjbind_ty_2 = 17
public const AVIF_TRANSFER_CHARACTERISTICS_HLG: _cjbind_ty_2 = 18

public type _cjbind_ty_2 = UInt32

public type avifTransferCharacteristics = UInt16

foreign func avifTransferCharacteristicsGetGamma(atc: avifTransferCharacteristics, gamma: CPointer<Float32>): avifResult

foreign func avifTransferCharacteristicsFindByGamma(gamma: Float32): avifTransferCharacteristics

public const AVIF_MATRIX_COEFFICIENTS_IDENTITY: _cjbind_ty_3 = 0
public const AVIF_MATRIX_COEFFICIENTS_BT709: _cjbind_ty_3 = 1
public const AVIF_MATRIX_COEFFICIENTS_UNSPECIFIED: _cjbind_ty_3 = 2
public const AVIF_MATRIX_COEFFICIENTS_FCC: _cjbind_ty_3 = 4
public const AVIF_MATRIX_COEFFICIENTS_BT470BG: _cjbind_ty_3 = 5
public const AVIF_MATRIX_COEFFICIENTS_BT601: _cjbind_ty_3 = 6
public const AVIF_MATRIX_COEFFICIENTS_SMPTE240: _cjbind_ty_3 = 7
public const AVIF_MATRIX_COEFFICIENTS_YCGCO: _cjbind_ty_3 = 8
public const AVIF_MATRIX_COEFFICIENTS_BT2020_NCL: _cjbind_ty_3 = 9
public const AVIF_MATRIX_COEFFICIENTS_BT2020_CL: _cjbind_ty_3 = 10
public const AVIF_MATRIX_COEFFICIENTS_SMPTE2085: _cjbind_ty_3 = 11
public const AVIF_MATRIX_COEFFICIENTS_CHROMA_DERIVED_NCL: _cjbind_ty_3 = 12
public const AVIF_MATRIX_COEFFICIENTS_CHROMA_DERIVED_CL: _cjbind_ty_3 = 13
public const AVIF_MATRIX_COEFFICIENTS_ICTCP: _cjbind_ty_3 = 14
public const AVIF_MATRIX_COEFFICIENTS_LAST: _cjbind_ty_3 = 15

public type _cjbind_ty_3 = UInt32

public type avifMatrixCoefficients = UInt16

@C
public struct avifDiagnostics {
    public let error: VArray<UInt8, $256>

    public init(error: VArray<UInt8, $256>) {
        this.error = error
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifDiagnostics>()
        if (size != 256) {
            throw Exception("Size of avifDiagnostics is not 256 but ${size} bytes")
        }
        let align = alignOf<avifDiagnostics>()
        if (align != 1) {
            throw Exception("Alignment of avifDiagnostics is not 1 but ${align} bytes")
        }
}

foreign func avifDiagnosticsClearError(diag: CPointer<avifDiagnostics>): Unit

@C
public struct avifFraction {
    public let n: Int32
    public let d: Int32

    public init(n: Int32, d: Int32) {
        this.n = n
        this.d = d
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifFraction>()
        if (size != 8) {
            throw Exception("Size of avifFraction is not 8 but ${size} bytes")
        }
        let align = alignOf<avifFraction>()
        if (align != 4) {
            throw Exception("Alignment of avifFraction is not 4 but ${align} bytes")
        }
}

public const avifTransformFlag_AVIF_TRANSFORM_NONE: avifTransformFlag = 0
public const avifTransformFlag_AVIF_TRANSFORM_PASP: avifTransformFlag = 1
public const avifTransformFlag_AVIF_TRANSFORM_CLAP: avifTransformFlag = 2
public const avifTransformFlag_AVIF_TRANSFORM_IROT: avifTransformFlag = 4
public const avifTransformFlag_AVIF_TRANSFORM_IMIR: avifTransformFlag = 8

public type avifTransformFlag = UInt32

public type avifTransformFlags = UInt32

@C
public struct avifPixelAspectRatioBox {
    public let hSpacing: UInt32
    public let vSpacing: UInt32

    public init(hSpacing: UInt32, vSpacing: UInt32) {
        this.hSpacing = hSpacing
        this.vSpacing = vSpacing
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifPixelAspectRatioBox>()
        if (size != 8) {
            throw Exception("Size of avifPixelAspectRatioBox is not 8 but ${size} bytes")
        }
        let align = alignOf<avifPixelAspectRatioBox>()
        if (align != 4) {
            throw Exception("Alignment of avifPixelAspectRatioBox is not 4 but ${align} bytes")
        }
}

@C
public struct avifCleanApertureBox {
    public let widthN: UInt32
    public let widthD: UInt32
    public let heightN: UInt32
    public let heightD: UInt32
    public let horizOffN: UInt32
    public let horizOffD: UInt32
    public let vertOffN: UInt32
    public let vertOffD: UInt32

    public init(widthN: UInt32, widthD: UInt32, heightN: UInt32, heightD: UInt32, horizOffN: UInt32, horizOffD: UInt32,
        vertOffN: UInt32, vertOffD: UInt32) {
        this.widthN = widthN
        this.widthD = widthD
        this.heightN = heightN
        this.heightD = heightD
        this.horizOffN = horizOffN
        this.horizOffD = horizOffD
        this.vertOffN = vertOffN
        this.vertOffD = vertOffD
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifCleanApertureBox>()
        if (size != 32) {
            throw Exception("Size of avifCleanApertureBox is not 32 but ${size} bytes")
        }
        let align = alignOf<avifCleanApertureBox>()
        if (align != 4) {
            throw Exception("Alignment of avifCleanApertureBox is not 4 but ${align} bytes")
        }
}

@C
public struct avifImageRotation {
    public let angle: UInt8

    public init(angle: UInt8) {
        this.angle = angle
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifImageRotation>()
        if (size != 1) {
            throw Exception("Size of avifImageRotation is not 1 but ${size} bytes")
        }
        let align = alignOf<avifImageRotation>()
        if (align != 1) {
            throw Exception("Alignment of avifImageRotation is not 1 but ${align} bytes")
        }
}

@C
public struct avifImageMirror {
    public let axis: UInt8

    public init(axis: UInt8) {
        this.axis = axis
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifImageMirror>()
        if (size != 1) {
            throw Exception("Size of avifImageMirror is not 1 but ${size} bytes")
        }
        let align = alignOf<avifImageMirror>()
        if (align != 1) {
            throw Exception("Alignment of avifImageMirror is not 1 but ${align} bytes")
        }
}

@C
public struct avifCropRect {
    public let x: UInt32
    public let y: UInt32
    public let width: UInt32
    public let height: UInt32

    public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32) {
        this.x = x
        this.y = y
        this.width = width
        this.height = height
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifCropRect>()
        if (size != 16) {
            throw Exception("Size of avifCropRect is not 16 but ${size} bytes")
        }
        let align = alignOf<avifCropRect>()
        if (align != 4) {
            throw Exception("Alignment of avifCropRect is not 4 but ${align} bytes")
        }
}

foreign func avifCropRectConvertCleanApertureBox(cropRect: CPointer<avifCropRect>, clap: CPointer<avifCleanApertureBox>,
    imageW: UInt32, imageH: UInt32, yuvFormat: avifPixelFormat, diag: CPointer<avifDiagnostics>): avifBool

foreign func avifCleanApertureBoxConvertCropRect(clap: CPointer<avifCleanApertureBox>, cropRect: CPointer<avifCropRect>,
    imageW: UInt32, imageH: UInt32, yuvFormat: avifPixelFormat, diag: CPointer<avifDiagnostics>): avifBool

@C
public struct avifContentLightLevelInformationBox {
    public let maxCLL: UInt16
    public let maxPALL: UInt16

    public init(maxCLL: UInt16, maxPALL: UInt16) {
        this.maxCLL = maxCLL
        this.maxPALL = maxPALL
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifContentLightLevelInformationBox>()
        if (size != 4) {
            throw Exception("Size of avifContentLightLevelInformationBox is not 4 but ${size} bytes")
        }
        let align = alignOf<avifContentLightLevelInformationBox>()
        if (align != 2) {
            throw Exception("Alignment of avifContentLightLevelInformationBox is not 2 but ${align} bytes")
        }
}

@C
public struct avifImage {
    public let width: UInt32
    public let height: UInt32
    public let depth: UInt32
    public let yuvFormat: avifPixelFormat
    public let yuvRange: avifRange
    public let yuvChromaSamplePosition: avifChromaSamplePosition
    public let yuvPlanes: VArray<CString, $3>
    public let yuvRowBytes: VArray<UInt32, $3>
    public let imageOwnsYUVPlanes: avifBool
    public let alphaPlane: CString
    public let alphaRowBytes: UInt32
    public let imageOwnsAlphaPlane: avifBool
    public let alphaPremultiplied: avifBool
    public let icc: avifRWData
    public let colorPrimaries: avifColorPrimaries
    public let transferCharacteristics: avifTransferCharacteristics
    public let matrixCoefficients: avifMatrixCoefficients
    public let clli: avifContentLightLevelInformationBox
    public let transformFlags: avifTransformFlags
    public let pasp: avifPixelAspectRatioBox
    public let clap: avifCleanApertureBox
    public let irot: avifImageRotation
    public let imir: avifImageMirror
    public let exif: avifRWData
    public let xmp: avifRWData

    public init(width: UInt32, height: UInt32, depth: UInt32, yuvFormat: avifPixelFormat, yuvRange: avifRange,
        yuvChromaSamplePosition: avifChromaSamplePosition, yuvPlanes: VArray<CString, $3>,
        yuvRowBytes: VArray<UInt32, $3>, imageOwnsYUVPlanes: avifBool, alphaPlane: CString, alphaRowBytes: UInt32,
        imageOwnsAlphaPlane: avifBool, alphaPremultiplied: avifBool, icc: avifRWData,
        colorPrimaries: avifColorPrimaries, transferCharacteristics: avifTransferCharacteristics,
        matrixCoefficients: avifMatrixCoefficients, clli: avifContentLightLevelInformationBox,
        transformFlags: avifTransformFlags, pasp: avifPixelAspectRatioBox, clap: avifCleanApertureBox,
        irot: avifImageRotation, imir: avifImageMirror, exif: avifRWData, xmp: avifRWData) {
        this.width = width
        this.height = height
        this.depth = depth
        this.yuvFormat = yuvFormat
        this.yuvRange = yuvRange
        this.yuvChromaSamplePosition = yuvChromaSamplePosition
        this.yuvPlanes = yuvPlanes
        this.yuvRowBytes = yuvRowBytes
        this.imageOwnsYUVPlanes = imageOwnsYUVPlanes
        this.alphaPlane = alphaPlane
        this.alphaRowBytes = alphaRowBytes
        this.imageOwnsAlphaPlane = imageOwnsAlphaPlane
        this.alphaPremultiplied = alphaPremultiplied
        this.icc = icc
        this.colorPrimaries = colorPrimaries
        this.transferCharacteristics = transferCharacteristics
        this.matrixCoefficients = matrixCoefficients
        this.clli = clli
        this.transformFlags = transformFlags
        this.pasp = pasp
        this.clap = clap
        this.irot = irot
        this.imir = imir
        this.exif = exif
        this.xmp = xmp
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifImage>()
        if (size != 200) {
            throw Exception("Size of avifImage is not 200 but ${size} bytes")
        }
        let align = alignOf<avifImage>()
        if (align != 8) {
            throw Exception("Alignment of avifImage is not 8 but ${align} bytes")
        }
}

foreign func avifImageCreate(width: UInt32, height: UInt32, depth: UInt32, yuvFormat: avifPixelFormat): CPointer<avifImage>

foreign func avifImageCreateEmpty(): CPointer<avifImage>

foreign func avifImageCopy(dstImage: CPointer<avifImage>, srcImage: CPointer<avifImage>, planes: avifPlanesFlags): avifResult

foreign func avifImageSetViewRect(dstImage: CPointer<avifImage>, srcImage: CPointer<avifImage>,
    rect: CPointer<avifCropRect>): avifResult

foreign func avifImageDestroy(image: CPointer<avifImage>): Unit

foreign func avifImageSetProfileICC(image: CPointer<avifImage>, icc: CString, iccSize: UIntNative): avifResult

foreign func avifImageSetMetadataExif(image: CPointer<avifImage>, exif: CString, exifSize: UIntNative): avifResult

foreign func avifImageSetMetadataXMP(image: CPointer<avifImage>, xmp: CString, xmpSize: UIntNative): avifResult

foreign func avifImageAllocatePlanes(image: CPointer<avifImage>, planes: avifPlanesFlags): avifResult

foreign func avifImageFreePlanes(image: CPointer<avifImage>, planes: avifPlanesFlags): Unit

foreign func avifImageStealPlanes(dstImage: CPointer<avifImage>, srcImage: CPointer<avifImage>, planes: avifPlanesFlags): Unit

public const avifRGBFormat_AVIF_RGB_FORMAT_RGB: avifRGBFormat = 0
public const avifRGBFormat_AVIF_RGB_FORMAT_RGBA: avifRGBFormat = 1
public const avifRGBFormat_AVIF_RGB_FORMAT_ARGB: avifRGBFormat = 2
public const avifRGBFormat_AVIF_RGB_FORMAT_BGR: avifRGBFormat = 3
public const avifRGBFormat_AVIF_RGB_FORMAT_BGRA: avifRGBFormat = 4
public const avifRGBFormat_AVIF_RGB_FORMAT_ABGR: avifRGBFormat = 5
public const avifRGBFormat_AVIF_RGB_FORMAT_RGB_565: avifRGBFormat = 6
public const avifRGBFormat_AVIF_RGB_FORMAT_COUNT: avifRGBFormat = 7

public type avifRGBFormat = UInt32

foreign func avifRGBFormatChannelCount(format: avifRGBFormat): UInt32

foreign func avifRGBFormatHasAlpha(format: avifRGBFormat): avifBool

public const avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_AUTOMATIC: avifChromaUpsampling = 0
public const avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_FASTEST: avifChromaUpsampling = 1
public const avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_BEST_QUALITY: avifChromaUpsampling = 2
public const avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_NEAREST: avifChromaUpsampling = 3
public const avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_BILINEAR: avifChromaUpsampling = 4

public type avifChromaUpsampling = UInt32

public const avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_AUTOMATIC: avifChromaDownsampling = 0
public const avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_FASTEST: avifChromaDownsampling = 1
public const avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_BEST_QUALITY: avifChromaDownsampling = 2
public const avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_AVERAGE: avifChromaDownsampling = 3
public const avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_SHARP_YUV: avifChromaDownsampling = 4

public type avifChromaDownsampling = UInt32

@C
public struct avifRGBImage {
    public let width: UInt32
    public let height: UInt32
    public let depth: UInt32
    public let format: avifRGBFormat
    public let chromaUpsampling: avifChromaUpsampling
    public let chromaDownsampling: avifChromaDownsampling
    public let avoidLibYUV: avifBool
    public let ignoreAlpha: avifBool
    public let alphaPremultiplied: avifBool
    public let isFloat: avifBool
    public let maxThreads: Int32
    public let pixels: CString
    public let rowBytes: UInt32

    public init(width: UInt32, height: UInt32, depth: UInt32, format: avifRGBFormat,
        chromaUpsampling: avifChromaUpsampling, chromaDownsampling: avifChromaDownsampling, avoidLibYUV: avifBool,
        ignoreAlpha: avifBool, alphaPremultiplied: avifBool, isFloat: avifBool, maxThreads: Int32, pixels: CString,
        rowBytes: UInt32) {
        this.width = width
        this.height = height
        this.depth = depth
        this.format = format
        this.chromaUpsampling = chromaUpsampling
        this.chromaDownsampling = chromaDownsampling
        this.avoidLibYUV = avoidLibYUV
        this.ignoreAlpha = ignoreAlpha
        this.alphaPremultiplied = alphaPremultiplied
        this.isFloat = isFloat
        this.maxThreads = maxThreads
        this.pixels = pixels
        this.rowBytes = rowBytes
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifRGBImage>()
        if (size != 64) {
            throw Exception("Size of avifRGBImage is not 64 but ${size} bytes")
        }
        let align = alignOf<avifRGBImage>()
        if (align != 8) {
            throw Exception("Alignment of avifRGBImage is not 8 but ${align} bytes")
        }
}

foreign func avifRGBImageSetDefaults(rgb: CPointer<avifRGBImage>, image: CPointer<avifImage>): Unit

foreign func avifRGBImagePixelSize(rgb: CPointer<avifRGBImage>): UInt32

foreign func avifRGBImageAllocatePixels(rgb: CPointer<avifRGBImage>): avifResult

foreign func avifRGBImageFreePixels(rgb: CPointer<avifRGBImage>): Unit

foreign func avifImageRGBToYUV(image: CPointer<avifImage>, rgb: CPointer<avifRGBImage>): avifResult

foreign func avifImageYUVToRGB(image: CPointer<avifImage>, rgb: CPointer<avifRGBImage>): avifResult

foreign func avifRGBImagePremultiplyAlpha(rgb: CPointer<avifRGBImage>): avifResult

foreign func avifRGBImageUnpremultiplyAlpha(rgb: CPointer<avifRGBImage>): avifResult

foreign func avifFullToLimitedY(depth: UInt32, v: Int32): Int32

foreign func avifFullToLimitedUV(depth: UInt32, v: Int32): Int32

foreign func avifLimitedToFullY(depth: UInt32, v: Int32): Int32

foreign func avifLimitedToFullUV(depth: UInt32, v: Int32): Int32

public const avifCodecChoice_AVIF_CODEC_CHOICE_AUTO: avifCodecChoice = 0
public const avifCodecChoice_AVIF_CODEC_CHOICE_AOM: avifCodecChoice = 1
public const avifCodecChoice_AVIF_CODEC_CHOICE_DAV1D: avifCodecChoice = 2
public const avifCodecChoice_AVIF_CODEC_CHOICE_LIBGAV1: avifCodecChoice = 3
public const avifCodecChoice_AVIF_CODEC_CHOICE_RAV1E: avifCodecChoice = 4
public const avifCodecChoice_AVIF_CODEC_CHOICE_SVT: avifCodecChoice = 5
public const avifCodecChoice_AVIF_CODEC_CHOICE_AVM: avifCodecChoice = 6

public type avifCodecChoice = UInt32

public const avifCodecFlag_AVIF_CODEC_FLAG_CAN_DECODE: avifCodecFlag = 1
public const avifCodecFlag_AVIF_CODEC_FLAG_CAN_ENCODE: avifCodecFlag = 2

public type avifCodecFlag = UInt32

public type avifCodecFlags = UInt32

foreign func avifCodecName(choice: avifCodecChoice, requiredFlags: avifCodecFlags): CString

foreign func avifCodecChoiceFromName(name: CString): avifCodecChoice

public type avifIODestroyFunc = CFunc<(io: CPointer<avifIO>) -> Unit>

public type avifIOReadFunc = CFunc<(io: CPointer<avifIO>, readFlags: UInt32, offset: UInt64, size: UIntNative, out: CPointer<avifROData>) -> avifResult>

public type avifIOWriteFunc = CFunc<(io: CPointer<avifIO>, writeFlags: UInt32, offset: UInt64, data: CString,
    size: UIntNative) -> avifResult>

@C
public struct avifIO {
    public let destroy: avifIODestroyFunc
    public let read: avifIOReadFunc
    public let write: avifIOWriteFunc
    public let sizeHint: UInt64
    public let persistent: avifBool
    public let data: CPointer<Unit>

    public init(destroy: avifIODestroyFunc, read: avifIOReadFunc, write: avifIOWriteFunc, sizeHint: UInt64,
        persistent: avifBool, data: CPointer<Unit>) {
        this.destroy = destroy
        this.read = read
        this.write = write
        this.sizeHint = sizeHint
        this.persistent = persistent
        this.data = data
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifIO>()
        if (size != 48) {
            throw Exception("Size of avifIO is not 48 but ${size} bytes")
        }
        let align = alignOf<avifIO>()
        if (align != 8) {
            throw Exception("Alignment of avifIO is not 8 but ${align} bytes")
        }
}

foreign func avifIOCreateMemoryReader(data: CString, size: UIntNative): CPointer<avifIO>

foreign func avifIOCreateFileReader(filename: CString): CPointer<avifIO>

foreign func avifIODestroy(io: CPointer<avifIO>): Unit

public const avifStrictFlag_AVIF_STRICT_DISABLED: avifStrictFlag = 0
public const avifStrictFlag_AVIF_STRICT_PIXI_REQUIRED: avifStrictFlag = 1
public const avifStrictFlag_AVIF_STRICT_CLAP_VALID: avifStrictFlag = 2
public const avifStrictFlag_AVIF_STRICT_ALPHA_ISPE_REQUIRED: avifStrictFlag = 4
public const avifStrictFlag_AVIF_STRICT_ENABLED: avifStrictFlag = 7

public type avifStrictFlag = UInt32

public type avifStrictFlags = UInt32

@C
public struct avifIOStats {
    public let colorOBUSize: UIntNative
    public let alphaOBUSize: UIntNative

    public init(colorOBUSize: UIntNative, alphaOBUSize: UIntNative) {
        this.colorOBUSize = colorOBUSize
        this.alphaOBUSize = alphaOBUSize
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifIOStats>()
        if (size != 16) {
            throw Exception("Size of avifIOStats is not 16 but ${size} bytes")
        }
        let align = alignOf<avifIOStats>()
        if (align != 8) {
            throw Exception("Alignment of avifIOStats is not 8 but ${align} bytes")
        }
}

@C
public struct avifDecoderData {
    init() {
        throw Exception("type should not be inited")
    }
}

public const avifDecoderSource_AVIF_DECODER_SOURCE_AUTO: avifDecoderSource = 0
public const avifDecoderSource_AVIF_DECODER_SOURCE_PRIMARY_ITEM: avifDecoderSource = 1
public const avifDecoderSource_AVIF_DECODER_SOURCE_TRACKS: avifDecoderSource = 2

public type avifDecoderSource = UInt32

@C
public struct avifImageTiming {
    public let timescale: UInt64
    public let pts: Float64
    public let ptsInTimescales: UInt64
    public let duration: Float64
    public let durationInTimescales: UInt64

    public init(timescale: UInt64, pts: Float64, ptsInTimescales: UInt64, duration: Float64,
        durationInTimescales: UInt64) {
        this.timescale = timescale
        this.pts = pts
        this.ptsInTimescales = ptsInTimescales
        this.duration = duration
        this.durationInTimescales = durationInTimescales
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifImageTiming>()
        if (size != 40) {
            throw Exception("Size of avifImageTiming is not 40 but ${size} bytes")
        }
        let align = alignOf<avifImageTiming>()
        if (align != 8) {
            throw Exception("Alignment of avifImageTiming is not 8 but ${align} bytes")
        }
}

public const avifProgressiveState_AVIF_PROGRESSIVE_STATE_UNAVAILABLE: avifProgressiveState = 0
public const avifProgressiveState_AVIF_PROGRESSIVE_STATE_AVAILABLE: avifProgressiveState = 1
public const avifProgressiveState_AVIF_PROGRESSIVE_STATE_ACTIVE: avifProgressiveState = 2

public type avifProgressiveState = UInt32

foreign func avifProgressiveStateToString(progressiveState: avifProgressiveState): CString

@C
public struct avifDecoder {
    public let codecChoice: avifCodecChoice
    public let maxThreads: Int32
    public let requestedSource: avifDecoderSource
    public let allowProgressive: avifBool
    public let allowIncremental: avifBool
    public let ignoreExif: avifBool
    public let ignoreXMP: avifBool
    public let imageSizeLimit: UInt32
    public let imageDimensionLimit: UInt32
    public let imageCountLimit: UInt32
    public let strictFlags: avifStrictFlags
    public let image: CPointer<avifImage>
    public let imageIndex: Int32
    public let imageCount: Int32
    public let progressiveState: avifProgressiveState
    public let imageTiming: avifImageTiming
    public let timescale: UInt64
    public let duration: Float64
    public let durationInTimescales: UInt64
    public let repetitionCount: Int32
    public let alphaPresent: avifBool
    public let ioStats: avifIOStats
    public let diag: avifDiagnostics
    public let io: CPointer<avifIO>
    public let data: CPointer<avifDecoderData>

    public init(codecChoice: avifCodecChoice, maxThreads: Int32, requestedSource: avifDecoderSource,
        allowProgressive: avifBool, allowIncremental: avifBool, ignoreExif: avifBool, ignoreXMP: avifBool,
        imageSizeLimit: UInt32, imageDimensionLimit: UInt32, imageCountLimit: UInt32, strictFlags: avifStrictFlags,
        image: CPointer<avifImage>, imageIndex: Int32, imageCount: Int32, progressiveState: avifProgressiveState,
        imageTiming: avifImageTiming, timescale: UInt64, duration: Float64, durationInTimescales: UInt64,
        repetitionCount: Int32, alphaPresent: avifBool, ioStats: avifIOStats, diag: avifDiagnostics,
        io: CPointer<avifIO>, data: CPointer<avifDecoderData>) {
        this.codecChoice = codecChoice
        this.maxThreads = maxThreads
        this.requestedSource = requestedSource
        this.allowProgressive = allowProgressive
        this.allowIncremental = allowIncremental
        this.ignoreExif = ignoreExif
        this.ignoreXMP = ignoreXMP
        this.imageSizeLimit = imageSizeLimit
        this.imageDimensionLimit = imageDimensionLimit
        this.imageCountLimit = imageCountLimit
        this.strictFlags = strictFlags
        this.image = image
        this.imageIndex = imageIndex
        this.imageCount = imageCount
        this.progressiveState = progressiveState
        this.imageTiming = imageTiming
        this.timescale = timescale
        this.duration = duration
        this.durationInTimescales = durationInTimescales
        this.repetitionCount = repetitionCount
        this.alphaPresent = alphaPresent
        this.ioStats = ioStats
        this.diag = diag
        this.io = io
        this.data = data
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifDecoder>()
        if (size != 432) {
            throw Exception("Size of avifDecoder is not 432 but ${size} bytes")
        }
        let align = alignOf<avifDecoder>()
        if (align != 8) {
            throw Exception("Alignment of avifDecoder is not 8 but ${align} bytes")
        }
}

foreign func avifDecoderCreate(): CPointer<avifDecoder>

foreign func avifDecoderDestroy(decoder: CPointer<avifDecoder>): Unit

foreign func avifDecoderRead(decoder: CPointer<avifDecoder>, image: CPointer<avifImage>): avifResult

foreign func avifDecoderReadMemory(decoder: CPointer<avifDecoder>, image: CPointer<avifImage>, data: CString,
    size: UIntNative): avifResult

foreign func avifDecoderReadFile(decoder: CPointer<avifDecoder>, image: CPointer<avifImage>, filename: CString): avifResult

foreign func avifDecoderSetSource(decoder: CPointer<avifDecoder>, source: avifDecoderSource): avifResult

foreign func avifDecoderSetIO(decoder: CPointer<avifDecoder>, io: CPointer<avifIO>): Unit

foreign func avifDecoderSetIOMemory(decoder: CPointer<avifDecoder>, data: CString, size: UIntNative): avifResult

foreign func avifDecoderSetIOFile(decoder: CPointer<avifDecoder>, filename: CString): avifResult

foreign func avifDecoderParse(decoder: CPointer<avifDecoder>): avifResult

foreign func avifDecoderNextImage(decoder: CPointer<avifDecoder>): avifResult

foreign func avifDecoderNthImage(decoder: CPointer<avifDecoder>, frameIndex: UInt32): avifResult

foreign func avifDecoderReset(decoder: CPointer<avifDecoder>): avifResult

foreign func avifDecoderIsKeyframe(decoder: CPointer<avifDecoder>, frameIndex: UInt32): avifBool

foreign func avifDecoderNearestKeyframe(decoder: CPointer<avifDecoder>, frameIndex: UInt32): UInt32

foreign func avifDecoderNthImageTiming(decoder: CPointer<avifDecoder>, frameIndex: UInt32,
    outTiming: CPointer<avifImageTiming>): avifResult

foreign func avifDecoderDecodedRowCount(decoder: CPointer<avifDecoder>): UInt32

@C
public struct avifExtent {
    public let offset: UInt64
    public let size: UIntNative

    public init(offset: UInt64, size: UIntNative) {
        this.offset = offset
        this.size = size
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifExtent>()
        if (size != 16) {
            throw Exception("Size of avifExtent is not 16 but ${size} bytes")
        }
        let align = alignOf<avifExtent>()
        if (align != 8) {
            throw Exception("Alignment of avifExtent is not 8 but ${align} bytes")
        }
}

foreign func avifDecoderNthImageMaxExtent(decoder: CPointer<avifDecoder>, frameIndex: UInt32,
    outExtent: CPointer<avifExtent>): avifResult

@C
public struct avifEncoderData {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct avifCodecSpecificOptions {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct avifScalingMode {
    public let horizontal: avifFraction
    public let vertical: avifFraction

    public init(horizontal: avifFraction, vertical: avifFraction) {
        this.horizontal = horizontal
        this.vertical = vertical
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifScalingMode>()
        if (size != 16) {
            throw Exception("Size of avifScalingMode is not 16 but ${size} bytes")
        }
        let align = alignOf<avifScalingMode>()
        if (align != 4) {
            throw Exception("Alignment of avifScalingMode is not 4 but ${align} bytes")
        }
}

@C
public struct avifEncoder {
    public let codecChoice: avifCodecChoice
    public let maxThreads: Int32
    public let speed: Int32
    public let keyframeInterval: Int32
    public let timescale: UInt64
    public let repetitionCount: Int32
    public let extraLayerCount: UInt32
    public let quality: Int32
    public let qualityAlpha: Int32
    public let minQuantizer: Int32
    public let maxQuantizer: Int32
    public let minQuantizerAlpha: Int32
    public let maxQuantizerAlpha: Int32
    public let tileRowsLog2: Int32
    public let tileColsLog2: Int32
    public let autoTiling: avifBool
    public let scalingMode: avifScalingMode
    public let ioStats: avifIOStats
    public let diag: avifDiagnostics
    public let data: CPointer<avifEncoderData>
    public let csOptions: CPointer<avifCodecSpecificOptions>

    public init(codecChoice: avifCodecChoice, maxThreads: Int32, speed: Int32, keyframeInterval: Int32,
        timescale: UInt64, repetitionCount: Int32, extraLayerCount: UInt32, quality: Int32, qualityAlpha: Int32,
        minQuantizer: Int32, maxQuantizer: Int32, minQuantizerAlpha: Int32, maxQuantizerAlpha: Int32,
        tileRowsLog2: Int32, tileColsLog2: Int32, autoTiling: avifBool, scalingMode: avifScalingMode,
        ioStats: avifIOStats, diag: avifDiagnostics, data: CPointer<avifEncoderData>,
        csOptions: CPointer<avifCodecSpecificOptions>) {
        this.codecChoice = codecChoice
        this.maxThreads = maxThreads
        this.speed = speed
        this.keyframeInterval = keyframeInterval
        this.timescale = timescale
        this.repetitionCount = repetitionCount
        this.extraLayerCount = extraLayerCount
        this.quality = quality
        this.qualityAlpha = qualityAlpha
        this.minQuantizer = minQuantizer
        this.maxQuantizer = maxQuantizer
        this.minQuantizerAlpha = minQuantizerAlpha
        this.maxQuantizerAlpha = maxQuantizerAlpha
        this.tileRowsLog2 = tileRowsLog2
        this.tileColsLog2 = tileColsLog2
        this.autoTiling = autoTiling
        this.scalingMode = scalingMode
        this.ioStats = ioStats
        this.diag = diag
        this.data = data
        this.csOptions = csOptions
    }
}

@When[debug]
let _ = {
    =>
        let size = sizeOf<avifEncoder>()
        if (size != 376) {
            throw Exception("Size of avifEncoder is not 376 but ${size} bytes")
        }
        let align = alignOf<avifEncoder>()
        if (align != 8) {
            throw Exception("Alignment of avifEncoder is not 8 but ${align} bytes")
        }
}

foreign func avifEncoderCreate(): CPointer<avifEncoder>

foreign func avifEncoderWrite(encoder: CPointer<avifEncoder>, image: CPointer<avifImage>, output: CPointer<avifRWData>): avifResult

foreign func avifEncoderDestroy(encoder: CPointer<avifEncoder>): Unit

public const avifAddImageFlag_AVIF_ADD_IMAGE_FLAG_NONE: avifAddImageFlag = 0
public const avifAddImageFlag_AVIF_ADD_IMAGE_FLAG_FORCE_KEYFRAME: avifAddImageFlag = 1
public const avifAddImageFlag_AVIF_ADD_IMAGE_FLAG_SINGLE: avifAddImageFlag = 2

public type avifAddImageFlag = UInt32

public type avifAddImageFlags = UInt32

foreign func avifEncoderAddImage(encoder: CPointer<avifEncoder>, image: CPointer<avifImage>,
    durationInTimescales: UInt64, addImageFlags: avifAddImageFlags): avifResult

foreign func avifEncoderAddImageGrid(encoder: CPointer<avifEncoder>, gridCols: UInt32, gridRows: UInt32,
    cellImages: CPointer<CPointer<avifImage>>, addImageFlags: avifAddImageFlags): avifResult

foreign func avifEncoderFinish(encoder: CPointer<avifEncoder>, output: CPointer<avifRWData>): avifResult

foreign func avifEncoderSetCodecSpecificOption(encoder: CPointer<avifEncoder>, key: CString, value: CString): avifResult

foreign func avifImageUsesU16(image: CPointer<avifImage>): avifBool

foreign func avifImageIsOpaque(image: CPointer<avifImage>): avifBool

foreign func avifImagePlane(image: CPointer<avifImage>, channel: Int32): CString

foreign func avifImagePlaneRowBytes(image: CPointer<avifImage>, channel: Int32): UInt32

foreign func avifImagePlaneWidth(image: CPointer<avifImage>, channel: Int32): UInt32

foreign func avifImagePlaneHeight(image: CPointer<avifImage>, channel: Int32): UInt32

foreign func avifPeekCompatibleFileType(input: CPointer<avifROData>): avifBool

public type __uint32_t = UInt32

public type __uint8_t = UInt8

public type __uint16_t = UInt16

public type __int32_t = Int32

public type __uint64_t = UInt64
