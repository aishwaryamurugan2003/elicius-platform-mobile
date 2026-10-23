/// The single place every backend route this app calls is defined — a port of
/// the web app's `src/services/apiService.tsx` (`Service`, `ServiceHost`,
/// `Endpoint`). Domain files in `lib/api/` only ever name an [Endpoint]; they
/// never build a URL by hand.
library;

/// One backend host per microservice.
enum Service {
  caas,
  deviceRegistration,
  visualization,
  dataDownloader,
  alerts,
  airQualityReports,
  mqttWs,
  deviceTelemetry,
}

/// Service -> base URL. Override any of them at build time, e.g.
/// `flutter run --dart-define=VISUALIZATION_HOST=http://10.0.2.2:8001`
/// (10.0.2.2 is the host machine as seen from the Android emulator).
class ServiceHost {
  ServiceHost._();

  static const _caas = String.fromEnvironment('CAAS_HOST', defaultValue: 'https://bs1.eliciusenergy.in');
  static const _deviceRegistration =
      String.fromEnvironment('DEVICE_REGISTRATION_HOST', defaultValue: 'https://bs2.eliciusenergy.in');
  static const _visualization = String.fromEnvironment('VISUALIZATION_HOST', defaultValue: 'https://bs4.eliciusenergy.in');
  static const _dataDownloader = String.fromEnvironment('DATA_DOWNLOADER_HOST', defaultValue: 'https://bs5.eliciusenergy.in');
  static const _alerts = String.fromEnvironment('ALERTS_HOST', defaultValue: 'https://bs7.eliciusenergy.in');
  static const _airQualityReports =
      String.fromEnvironment('AIR_QUALITY_REPORTS_HOST', defaultValue: 'https://bs6.eliciusenergy.in');
  // wss, not ws — the host force-redirects ws->wss and a WebSocket handshake can't follow redirects.
  static const _mqttWs = String.fromEnvironment('MQTT_WS_HOST', defaultValue: 'wss://bs3.eliciusenergy.in');
  static const _deviceTelemetry = String.fromEnvironment('DEVICE_TELEMETRY_HOST', defaultValue: 'https://bs4.eliciusenergy.in');

  static String of(Service s) => switch (s) {
        Service.caas => _caas,
        Service.deviceRegistration => _deviceRegistration,
        Service.visualization => _visualization,
        Service.dataDownloader => _dataDownloader,
        Service.alerts => _alerts,
        Service.airQualityReports => _airQualityReports,
        Service.mqttWs => _mqttWs,
        Service.deviceTelemetry => _deviceTelemetry,
      };
}

/// A route on one microservice. `{name}` placeholders are filled with [withParams].
class Endpoint {
  const Endpoint(this.service, this.path);

  final Service service;
  final String path;

  /// Fills `{name}` placeholders, URL-encoding each value.
  Endpoint withParams(Map<String, String> params) {
    var p = path;
    params.forEach((k, v) => p = p.replaceAll('{$k}', Uri.encodeComponent(v)));
    return Endpoint(service, p);
  }

  String get url => '${ServiceHost.of(service)}$path';

  // ---- Auth / organisations / mappings (CAAS)
  static const login = Endpoint(Service.caas, '/auth/login');
  static const myOrganization = Endpoint(Service.caas, '/organizations/me');
  static const organizations = Endpoint(Service.caas, '/organizations');
  static const organization = Endpoint(Service.caas, '/organizations/{org_id}');
  static const organizationMembers = Endpoint(Service.caas, '/organizations/{org_id}/members');
  static const organizationMember = Endpoint(Service.caas, '/organizations/{org_id}/members/{user_id}');
  static const keycloakUsers = Endpoint(Service.caas, '/keycloak/users');
  static const myGroupMappings = Endpoint(Service.caas, '/mappings/user');
  static const userGroupMappings = Endpoint(Service.caas, '/admin/mappings/{keycloak_user_id}');
  static const mappings = Endpoint(Service.caas, '/mappings');
  static const mapping = Endpoint(Service.caas, '/mappings/{mapping_id}');

  // ---- Device registration
  static const devices = Endpoint(Service.deviceRegistration, '/devices');
  static const device = Endpoint(Service.deviceRegistration, '/devices/{device_id}');
  static const mqttServers = Endpoint(Service.deviceRegistration, '/mqtt-servers');
  static const mqttServer = Endpoint(Service.deviceRegistration, '/mqtt-servers/{server_name}');
  static const groups = Endpoint(Service.deviceRegistration, '/groups');
  static const group = Endpoint(Service.deviceRegistration, '/groups/{group_id}');
  static const deviceTypes = Endpoint(Service.deviceRegistration, '/device-types');
  static const deviceType = Endpoint(Service.deviceRegistration, '/device-types/{id}');
  static const deviceTypeParameters = Endpoint(Service.deviceRegistration, '/device-types/{id}/parameters');
  static const monitoringFields = Endpoint(Service.deviceRegistration, '/device-types/{id}/parameters/monitoring-fields');
  static const monitoringField = Endpoint(Service.deviceRegistration, '/device-types/{id}/parameters/monitoring-fields/{key}');
  static const allFields = Endpoint(Service.deviceRegistration, '/device-types/{id}/parameters/all-fields');
  static const allField = Endpoint(Service.deviceRegistration, '/device-types/{id}/parameters/all-fields/{key}');
  static const deviceGroupLinks = Endpoint(Service.deviceRegistration, '/device-groups');
  static const deviceGroupLink = Endpoint(Service.deviceRegistration, '/device-groups/{id}');
  static const groupsForDevice = Endpoint(Service.deviceRegistration, '/device-groups/by-device/{device_id}');
  static const devicesForGroup = Endpoint(Service.deviceRegistration, '/device-groups/by-group/{group_id}');

  // ---- Visualization (folders, dashboards, plant views)
  static const folders = Endpoint(Service.visualization, '/v1/folders');
  static const folder = Endpoint(Service.visualization, '/v1/folders/{folder_id}');
  static const allFolders = Endpoint(Service.visualization, '/v1/allfolders');
  static const dashboards = Endpoint(Service.visualization, '/v1/dashboards');
  static const dashboardsInFolder = Endpoint(Service.visualization, '/v1/dashboards/folder/{folder_id}');
  static const dashboard = Endpoint(Service.visualization, '/v1/dashboards/{dashboard_id}');
  static const digitalTwins = Endpoint(Service.visualization, '/v1/digital-twins');
  static const digitalTwin = Endpoint(Service.visualization, '/v1/digital-twins/{twin_id}');
  static const digitalTwinImages = Endpoint(Service.visualization, '/v1/digital-twins/images');

  // ---- Telemetry (last packet, history, live stream)
  static const lastPacket = Endpoint(Service.deviceTelemetry, '/v1/devices/last-packet');
  static const telemetryData = Endpoint(Service.deviceTelemetry, '/v1/data');
  static const liveGroupStream = Endpoint(Service.mqttWs, '/stream/group/{group_id}');

  // ---- Alerts
  static const issuesSummary = Endpoint(Service.alerts, '/issues/summary');
  static const issuesTimeseries = Endpoint(Service.alerts, '/issues/timeseries');
  static const issues = Endpoint(Service.alerts, '/issues');
  static const issue = Endpoint(Service.alerts, '/issues/{id}');
  static const resolveIssue = Endpoint(Service.alerts, '/issues/{id}/resolve');
  static const triggerAction = Endpoint(Service.alerts, '/actions/trigger');
  static const actionsHistory = Endpoint(Service.alerts, '/actions/history');
  static const thresholds = Endpoint(Service.alerts, '/thresholds');
  static const monitoredDevices = Endpoint(Service.alerts, '/devices');
  static const deviceThresholds = Endpoint(Service.alerts, '/devices/{device_id}/thresholds');
  static const createDeviceThresholds = Endpoint(Service.alerts, '/thresholds/devices');
  static const threshold = Endpoint(Service.alerts, '/thresholds/{id}');

  // ---- Data downloader
  static const downloaderDbs = Endpoint(Service.dataDownloader, '/meta/dbs');
  static const downloaderCols = Endpoint(Service.dataDownloader, '/meta/dbs/{db}/cols');
  static const downloaderRowEstimate = Endpoint(Service.dataDownloader, '/meta/dbs/{db}/cols/ts');
  static const submitExport = Endpoint(Service.dataDownloader, '/job/data/download');
  static const jobStatus = Endpoint(Service.dataDownloader, '/job/status/{job_id}');
  static const jobHistory = Endpoint(Service.dataDownloader, '/job/history');
  static const downloadJob = Endpoint(Service.dataDownloader, '/job/download/{job_id}');

  // ---- AI reports
  static const reportTemplates = Endpoint(Service.airQualityReports, '/v1/templates');
  static const reportDevices = Endpoint(Service.airQualityReports, '/v1/devices');
  static const reports = Endpoint(Service.airQualityReports, '/v1/reports');
  static const generateReport = Endpoint(Service.airQualityReports, '/v1/reports/generate');
  static const report = Endpoint(Service.airQualityReports, '/v1/reports/{filename}');
  static const emailReport = Endpoint(Service.airQualityReports, '/v1/reports/{filename}/email');
  static const reportTaskStatus = Endpoint(Service.airQualityReports, '/v1/reports/task/{task_id}');
  static const viewReport = Endpoint(Service.airQualityReports, '/v1/reports/view/{filename}');
}
