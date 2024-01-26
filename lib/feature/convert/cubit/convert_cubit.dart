import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:collection/collection.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:mp3_convert/base_presentation/cubit/base_cubit.dart';
import 'package:mp3_convert/base_presentation/cubit/event_mixin.dart';
import 'package:mp3_convert/data/data_result.dart';
import 'package:mp3_convert/data/entity/app_file.dart';
import 'package:mp3_convert/data/entity/failure_entity.dart';
import 'package:mp3_convert/data/entity/feature.dart';
import 'package:mp3_convert/feature/convert/cubit/convert_event.dart';
import 'package:mp3_convert/feature/convert/cubit/convert_setting_cubit.dart';
import 'package:mp3_convert/feature/convert/cubit/convert_state.dart';
import 'package:mp3_convert/feature/convert/data/entity/convert_data.dart';
import 'package:mp3_convert/feature/convert/data/entity/get_mapping_type.dart';
import 'package:mp3_convert/feature/convert/data/entity/mapping_type.dart';
import 'package:mp3_convert/feature/convert/data/entity/media_type.dart';
import 'package:mp3_convert/feature/convert/data/entity/setting_file.dart';
import 'package:mp3_convert/feature/convert/data/repository/convert_file_repository.dart';
import 'package:mp3_convert/feature/convert/data/repository/convert_file_repository_impl.dart';
import 'package:mp3_convert/feature/convert/data/entity/pick_multiple_file.dart';
import 'package:mp3_convert/main.dart';
import 'package:mp3_convert/util/downloader_util.dart';
import 'package:mp3_convert/util/generate_string.dart';
import 'package:path_provider/path_provider.dart';

class ConvertCubit extends Cubit<ConvertState>
    with SafeEmit, EventMixin<HomeEvent>
    implements PickMultipleFile, MappingType {
  final GetMappingType _getMappingType = GetMappingType();

  final ConvertFileRepository convertFileRepository = ConvertFileRepositoryImpl();

  final DownloaderHelper _downloaderHelper = DownloaderHelper();

  final GenerateString generateString = UUIDGenerateString();

  List<ConfigConvertFile> get _files => state.files ?? [];

  ConvertCubit() : super(const ConvertEmptyState(maxFiles: 2)) {
    //use socket to listen convert progress from server
    socketChannel
      ..onConverting(_convertListener)
      ..onDisconnected(_onConvertingError);

    //use downloader to listen download progress from internet
    _downloaderHelper.startListen(_downloadListener);
  }

  @override
  Future<void> close() {
    _downloaderHelper.dispose();
    return super.close();
  }

  @override
  bool get canPickMultipleFile => state.canPickMultipleFile;

  @override
  Future<ListMediaType?> getMappingType(String sourceType) {
    return _getMappingType.getMappingType(sourceType);
  }

  @override
  Future<String?> getTypeName(String sourceType) {
    return _getMappingType.getTypeName(sourceType);
  }

  void _refreshPickedFileState() {
    emit(PickedFileState(files: [...?state.files], maxFiles: state.maxFiles));
  }

  void _setFileAtIndex(int index, ConfigConvertFile file) {
    try {
      state.files?[index] = file;

      _refreshPickedFileState();
    } catch (e) {}
  }

  void onRetry(int index, ConvertErrorFile file) {
    switch (file.convertStatusFile.status) {
      case ConvertStatus.uploading:
      case ConvertStatus.uploaded:
      case ConvertStatus.converting:
        onConvert(index, file);
        return;
      case ConvertStatus.converted:
      case ConvertStatus.downloading:
        downloadConvertedFile((file as HaveDownloadIdFile).downloadId ?? '');
        return;
      case ConvertStatus.downloaded:
        return;
    }
  }
}

extension ConvertListener on ConvertCubit {
  void _convertListener(dynamic data) {
    log("onConvert listener: ${data}");
    if (data is Map) {
      _updateConvertingProgress(data);
    } else if (data is String) {
      try {
        final decodeData = jsonDecode(data);
        if (decodeData is Map) {
          _updateConvertingProgress(decodeData);
        }
      } catch (e) {
        log("onConvert decode string error: $e");
      }
    }
  }

  void _updateConvertingProgress(Map data) {
    final convertData = ConvertData.fromMap(data);
    int index = state.files?.indexWhere((f) => f is ConvertingFile && f.uploadId == convertData.uploadId) ?? -1;
    if (index > -1) {
      final file = state.files![index];
      if (convertData.progress < 100 || convertData.downloadId == null) {
        state.files?[index] = (file as ConvertingFile).copyWith(
          convertProgress: convertData.progress / 100,
        );
      } else {
        state.files?[index] = ConvertedFile(
          downloadId: convertData.downloadId!,
          name: file.name,
          path: file.path,
          destinationType: file.destinationType,
        );

        if (AutoDownloadSetting().isAutoDownload()) {
          downloadConvertedFile(convertData.downloadId!);
        }
      }

      _refreshPickedFileState();
    }
  }

  void _onConvertingError(_) {
    _files.forEachIndexed((index, file) {
      if (file is ConvertingFile) {
        _setFileAtIndex(index, ConvertErrorFile(convertStatusFile: file));
      }
    });
  }
}

extension DownloadListener on ConvertCubit {
  void _downloadListener(dynamic data) {
    String id = data[0];

    ///1: _
    ///2: running
    ///3: complete
    ///4: error
    int status = data[1];
    int progress = data[2];
    int index = state.files?.indexWhere((f) {
          return _checkIsDownloadingFile(f, id) || _checkIsDownloadingFileFromError(f, id);
        }) ??
        -1;

    if (index < 0) {
      return;
    }

    final DownloadingFile file = _getDownloadingFile(state.files![index]);

    if (status == 4) {
      _setFileAtIndex(index, ConvertErrorFile(convertStatusFile: file));
      return;
    }

    if (progress < 100) {
      _setFileAtIndex(index, file.copyWith(downloadProgress: progress / 100));
    } else {
      _setFileAtIndex(
        index,
        DownloadedFile(
          destinationType: file.destinationType,
          path: file.path,
          name: file.name,
          downloadPath: file.downloadPath,
        ),
      );
    }
  }

  bool _checkIsDownloadingFile(ConfigConvertFile f, String id) {
    return f is DownloadingFile && f.downloaderId == id;
  }

  bool _checkIsDownloadingFileFromError(ConfigConvertFile f, String id) {
    return f is ConvertErrorFile && _checkIsDownloadingFile(f.convertStatusFile, id);
  }

  DownloadingFile _getDownloadingFile(ConfigConvertFile f) {
    if (f is DownloadingFile) {
      return f;
    } else if (f is ConvertErrorFile) {
      return _getDownloadingFile(f.convertStatusFile);
    }
    throw Exception("Can not get DownloadingFile");
  }
}

extension FileManager on ConvertCubit {
  void setPickedFiles(List<ConfigConvertFile> files) {
    final newFiles = validateFiles(files);

    if (newFiles.isEmpty) {
      return;
    }

    emit(PickedFileState(files: newFiles, maxFiles: state.maxFiles));
  }

  void addPickedFiles(List<ConfigConvertFile> files) {
    final newFiles = validateFiles(files);

    if (newFiles.isEmpty) {
      return;
    }

    emit(PickedFileState(files: [...?state.files, ...newFiles], maxFiles: state.maxFiles));
  }

  void updateDestinationType(
    int index,
    ConfigConvertFile current,
    String type,
  ) {
    _setFileAtIndex(
      index,
      ConfigConvertFile(
        name: current.name,
        path: current.path,
        destinationType: type,
      ),
    );
  }

  void updateDestinationTypeForAll(
    String type,
  ) {
    for (int i = 0; i < _files.length; i++) {
      if (_files[i].destinationType == null) {
        updateDestinationType(
          i,
          _files[i],
          type,
        );
      }
    }
  }

  List<ConfigConvertFile> validateFiles(List<ConfigConvertFile> files) {
    List<ConfigConvertFile> newFiles = [];

    for (var file in files) {
      try {
        file.type;
        newFiles.add(file);
      } catch (e) {
        if (e is UnknownFileTypeException) {
          log("Have unknown file type");
        } else {
          log("validate file type: ${e.toString()}");
        }
      }
    }

    return newFiles;
  }

  void removeFile(AppFile file) {
    final cloneFiles = [...?state.files];
    cloneFiles.remove(file);
    if (cloneFiles.isEmpty) {
      emit(ConvertEmptyState(maxFiles: state.maxFiles));
    } else {
      emit(PickedFileState(
        maxFiles: state.maxFiles,
        files: cloneFiles,
      ));
    }
  }

  void removeFileByIndex(int index) {
    final cloneFiles = [...?state.files];
    final file = cloneFiles.removeAt(index);
    if (cloneFiles.isEmpty) {
      emit(ConvertEmptyState(maxFiles: state.maxFiles));
    } else {
      emit(PickedFileState(
        maxFiles: state.maxFiles,
        files: cloneFiles,
      ));
    }
    if (file is DownloadingFile) {
      FlutterDownloader.cancel(taskId: file.downloaderId ?? '');
    }
  }

  void _validateConvertAll() {
    ////note: duyệt theo cách này sẽ đi tuần tự hết list
    if ([for (int i = 0; i < _files.length; i++) _validateFileIndex(i)].contains(false)) {
      throw UnknownFileTypeException();
    }

    ////note: duyệt theo cách này mapping song song
    // if (_files.mapIndexed((index, _) => _validateFileIndex(index)).contains(false)) {
    //   throw UnknownFileTypeException();
    // }
  }

  bool _validateFileIndex(int index) {
    final file = _files[index];

    if (file.destinationType == null) {
      _setFileAtIndex(
        index,
        UnValidConfigConvertFile(
          name: file.name,
          path: file.path,
          destinationType: file.destinationType,
        ),
      );
      return false;
    }
    return true;
  }
}

class UnknownDestinationFileType implements Exception {}

extension ConvertingFileProcess on ConvertCubit {
  String? get socketId => socketChannel.socketId;

  Future onConvertAll() async {
    if (state.files?.isEmpty ?? true) {
      return;
    }

    try {
      _validateConvertAll();

      _files.forEachIndexed((index, file) {
        onConvert(index, file);
      });
    } catch (e, st) {
      if (e is UnknownFileTypeException) {
        addEvent(UnknownDestinationEvent());
      }
      return;
    }
  }

  //add row
  Future onAddRow(int index, ConfigConvertFile file) async {
    final uploadId = generateString.getString();
    final uploadingFile = UploadingFile(
      name: file.name,
      path: file.path,
      destinationType: file.destinationType,
      uploadId: uploadId,
    );

    _setFileAtIndex(index, uploadingFile);

    if (socketId == null) {
      _setFileAtIndex(index, ConvertErrorFile(convertStatusFile: uploadingFile));
      return;
    }

    final addRowResult = await convertFileRepository.addRow(
      AddRowRequestData(
        socketId: socketId!,
        sessionId: generateString.getString(),
        fileName: uploadingFile.name,
        uploadId: uploadingFile.uploadId,
        target: uploadingFile.destinationType!,
        ext: uploadingFile.type,
        fileType: (await getTypeName(uploadingFile.type)) ?? '',
        feature: AppFeature.convert,
        fileSize: FileStat.statSync(file.path).size,
      ),
    );

    final updateIndex = _files.indexWhere((f) => f is UploadingFile && f.uploadId == uploadId);

    if (updateIndex >= 0) {
      switch (addRowResult) {
        case SuccessDataResult<FailureEntity, dynamic>():
          onUploadFile(updateIndex, uploadingFile);
          return;
        case FailureDataResult<FailureEntity, dynamic>():
          _setFileAtIndex(updateIndex, ConvertErrorFile(convertStatusFile: uploadingFile));
          return;
      }
    }
  }

  //upload file

  Future onUploadFile(int index, UploadingFile file) async {
    final uploadResult = await convertFileRepository.uploadFile(
      UploadRequestData(
        fileName: file.name,
        uploadId: file.uploadId,
        filePath: file.path,
        fileType: file.type,
      ),
    );

    final updateIndex = _files.indexWhere((f) => f is UploadingFile && f.uploadId == file.uploadId);
    if (updateIndex >= 0) {
      switch (uploadResult) {
        case SuccessDataResult<FailureEntity, dynamic>():
          _setFileAtIndex(
            index,
            UploadedFile(
              name: file.name,
              path: file.path,
              destinationType: file.destinationType,
              uploadId: file.uploadId,
            ),
          );

          _setFileAtIndex(
            index,
            ConvertingFile(
              name: file.name,
              path: file.path,
              destinationType: file.destinationType,
              uploadId: file.uploadId,
              convertProgress: .0,
            ),
          );

          return;
        case FailureDataResult<FailureEntity, dynamic>():
          _setFileAtIndex(index, ConvertErrorFile(convertStatusFile: file));
          return;
      }
    }
  }

  //convert file
  Future onConvert(int index, ConfigConvertFile file) async {
    ///Check if this file is in converting progress
    ///Ignore it
    if (file is ConvertStatusFile) {
      return;
    }

    onAddRow(index, file);
  }

  //download file

  void downloadConvertedFile(String downloadId) async {
    int index = state.files?.indexWhere((f) => f is ConvertedFile && f.downloadId == downloadId) ?? -1;

    if (index < 0) {
      return;
    }

    final String path = await _getPath();

    final ConvertedFile file = state.files![index] as ConvertedFile;
    final fileName = '${file.generateConvertFileName()}';
    final downloadPath = '$path/$fileName';

    final downloadingFile = DownloadingFile(
      name: file.name,
      path: file.path,
      destinationType: file.destinationType,
      downloadId: file.downloadId,
      downloadProgress: .0,
      downloadPath: downloadPath,
      downloaderId: null,
    );

    _setFileAtIndex(index, downloadingFile);

    final downloadResult = await convertFileRepository.download(DownloadRequestData(
      downloadId: downloadId,
      savePath: path,
      fileName: fileName,
    ));

    switch (downloadResult) {
      case SuccessDataResult<FailureEntity, String>():
        final downloaderId = downloadResult.data;
        log("added ${downloaderId} to FlutterDownloader.enqueue");
        _setFileAtIndex(index, downloadingFile.copyWith(downloaderId: downloaderId));
        break;
      case FailureDataResult<FailureEntity, dynamic>():
        log("cannot get downloader id");
        addEvent(CannotDownloadFileEvent());
    }
  }

  Future<String> _getPath() async {
    return getPath();
  }
}

Future<String> getPath() async {
  late final Directory downloadsDir;
  if (Platform.isAndroid) {
    downloadsDir = Directory('/storage/emulated/0/Download');
  } else {
    downloadsDir = await getApplicationDocumentsDirectory();
  }

  final savedDir = Directory("${downloadsDir.absolute.path}/mp3_convert");

  if (!savedDir.existsSync()) {
    await savedDir.create();
  }
  return savedDir.absolute.path;
}
