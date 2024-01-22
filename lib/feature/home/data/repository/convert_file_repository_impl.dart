import 'package:mp3_convert/data/data_result.dart';
import 'package:mp3_convert/data/entity/failure_entity.dart';
import 'package:mp3_convert/data/request_data.dart';
import 'package:mp3_convert/feature/home/data/data_source/file_data_source.dart';
import 'package:mp3_convert/feature/home/data/data_source/file_data_source_impl.dart';
import 'package:mp3_convert/feature/home/data/repository/convert_file_repository.dart';
import 'package:mp3_convert/internet_connect/http_request/api.dart';
import 'package:mp3_convert/internet_connect/http_request/api_dto.dart';
import 'package:mp3_convert/internet_connect/http_request/api_response.dart';

class ConvertFileRepositoryImpl extends ConvertFileRepository {
  final FileDataSource _fileDataSource = FileDataSourceImpl(UploadApiRequest());
  @override
  Future<DataResult<FailureEntity, dynamic>> addRow(AddRowRequestData requestData) {
    return _fileDataSource.addRow(requestData.toDto()).then((response) {
      switch (response) {
        case SuccessApiResponse():
          final responseData = response.data;
          if (responseData is Map) {
            return SuccessDataResult(responseData);
          }
        case FailureApiResponse():
          return FailureDataResult(FailureEntity(message: response.message));
        case InternetErrorResponse():
        // TODO: Handle this case.
      }
      return FailureDataResult(FailureEntity(message: response.message));
    });
  }

  @override
  Future<DataResult<FailureEntity, dynamic>> uploadFile(UploadRequestData requestData) {
    return _fileDataSource.uploadFile(requestData.toDto()).then((response) {
      switch (response) {
        case SuccessApiResponse():
          final responseData = response.data;
          return SuccessDataResult(responseData);
        case FailureApiResponse():
          return FailureDataResult(FailureEntity(message: response.message));
        case InternetErrorResponse():
          return FailureDataResult(FailureEntity(message: response.message));
      }
    });
  }

  @override
  Future<DataResult<FailureEntity, dynamic>> download(DownloadRequestData requestData) {
    return _fileDataSource.downloadFile(requestData.toDto()).then((response) {
      switch (response) {
        case SuccessApiResponse():
          final responseData = response.data;
          if (responseData is Map) {
            return SuccessDataResult(responseData);
          }
        case FailureApiResponse():
          return FailureDataResult(FailureEntity(message: response.message));
        case InternetErrorResponse():
        // TODO: Handle this case.
      }
      return FailureDataResult(FailureEntity(message: response.message));
    });
  }
}
