package rifle

//TODO: This will eventually become some large tagged union with a bunch of specific error types

RifleError :: enum {
	None,
	AllocatorError,
	BufferTooSmallError,
	IndexOutOfBoundsError,
	InvalidArgError,
	FileOperationError,
	GenericError,
	FileNotReady,
	UnsupportedPlatformError,
	UnimplementedError,
	InvalidFileFormatError,
}
