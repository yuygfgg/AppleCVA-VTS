#ifndef VTS_SOURCE_QT_CONTROLLER_H
#define VTS_SOURCE_QT_CONTROLLER_H

#include <QObject>
#include <QString>
#include <QStringList>

#include <memory>

class VTSController final : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString host READ host NOTIFY hostChanged)
    Q_PROPERTY(int port READ port NOTIFY portChanged)
    Q_PROPERTY(
        QStringList cameraNames READ cameraNames NOTIFY cameraNamesChanged)
    Q_PROPERTY(int cameraIndex READ cameraIndex NOTIFY cameraIndexChanged)
    Q_PROPERTY(int backendMode READ backendMode WRITE setBackendMode NOTIFY
                   backendModeChanged)
    Q_PROPERTY(bool enableFilter READ enableFilter WRITE setEnableFilter NOTIFY
                   enableFilterChanged)
    Q_PROPERTY(
        bool includeCustomParameters READ includeCustomParameters WRITE
            setIncludeCustomParameters NOTIFY includeCustomParametersChanged)
    Q_PROPERTY(bool includeARKitAliases READ includeARKitAliases WRITE
                   setIncludeARKitAliases NOTIFY includeARKitAliasesChanged)
    Q_PROPERTY(bool includeACVABlendshapeParameters READ
                   includeACVABlendshapeParameters WRITE
                       setIncludeACVABlendshapeParameters NOTIFY
                           includeACVABlendshapeParametersChanged)
    Q_PROPERTY(bool mirrorPreview READ mirrorPreview WRITE setMirrorPreview
                   NOTIFY mirrorPreviewChanged)
    Q_PROPERTY(bool showCameraPreview READ showCameraPreview WRITE
                   setShowCameraPreview NOTIFY showCameraPreviewChanged)
    Q_PROPERTY(bool flipLandmarkY READ flipLandmarkY WRITE setFlipLandmarkY
                   NOTIFY flipLandmarkYChanged)
    Q_PROPERTY(bool topLeftOrigin READ topLeftOrigin WRITE setTopLeftOrigin
                   NOTIFY topLeftOriginChanged)
    Q_PROPERTY(double oneEuroMinCutoff READ oneEuroMinCutoff WRITE
                   setOneEuroMinCutoff NOTIFY oneEuroParametersChanged)
    Q_PROPERTY(double oneEuroBeta READ oneEuroBeta WRITE setOneEuroBeta NOTIFY
                   oneEuroParametersChanged)
    Q_PROPERTY(double oneEuroDerivativeCutoff READ oneEuroDerivativeCutoff WRITE
                   setOneEuroDerivativeCutoff NOTIFY oneEuroParametersChanged)
    Q_PROPERTY(QString message READ message NOTIFY statusChanged)
    Q_PROPERTY(
        QString extraStatusLine READ extraStatusLine NOTIFY statusChanged)
    Q_PROPERTY(double fps READ fps NOTIFY trackingStatsChanged)
    Q_PROPERTY(int detectedFaceCount READ detectedFaceCount NOTIFY
                   trackingStatsChanged)
    Q_PROPERTY(
        int trackedFaceCount READ trackedFaceCount NOTIFY trackingStatsChanged)
    Q_PROPERTY(bool hasFace READ hasFace NOTIFY trackingStatsChanged)
    Q_PROPERTY(double confidence READ confidence NOTIFY trackingStatsChanged)
    Q_PROPERTY(QString calibrationButtonText READ calibrationButtonText NOTIFY
                   calibrationStateChanged)
    Q_PROPERTY(bool calibrationBusy READ calibrationBusy NOTIFY
                   calibrationStateChanged)
    Q_PROPERTY(int calibrationSampleCount READ calibrationSampleCount NOTIFY
                   calibrationStateChanged)
    Q_PROPERTY(int calibrationSampleTarget READ calibrationSampleTarget NOTIFY
                   calibrationStateChanged)

  public:
    struct Impl;

    explicit VTSController(QObject* parent = nullptr);
    ~VTSController() override;

    QString host() const;
    int port() const;
    QStringList cameraNames() const;
    int cameraIndex() const;

    int backendMode() const;
    void setBackendMode(int mode);

    bool enableFilter() const;
    void setEnableFilter(bool enabled);

    bool includeCustomParameters() const;
    void setIncludeCustomParameters(bool enabled);

    bool includeARKitAliases() const;
    void setIncludeARKitAliases(bool enabled);

    bool includeACVABlendshapeParameters() const;
    void setIncludeACVABlendshapeParameters(bool enabled);

    bool mirrorPreview() const;
    void setMirrorPreview(bool enabled);

    bool showCameraPreview() const;
    void setShowCameraPreview(bool enabled);

    bool flipLandmarkY() const;
    void setFlipLandmarkY(bool enabled);

    bool topLeftOrigin() const;
    void setTopLeftOrigin(bool enabled);

    double oneEuroMinCutoff() const;
    void setOneEuroMinCutoff(double value);

    double oneEuroBeta() const;
    void setOneEuroBeta(double value);

    double oneEuroDerivativeCutoff() const;
    void setOneEuroDerivativeCutoff(double value);

    QString message() const;
    QString extraStatusLine() const;
    double fps() const;
    int detectedFaceCount() const;
    int trackedFaceCount() const;
    bool hasFace() const;
    double confidence() const;

    QString calibrationButtonText() const;
    bool calibrationBusy() const;
    int calibrationSampleCount() const;
    int calibrationSampleTarget() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void setPreviewItem(QObject* item);
    Q_INVOKABLE void applyConnection(const QString& host,
                                     const QString& portText);
    Q_INVOKABLE void setCameraIndex(int index);
    Q_INVOKABLE void refreshCameras();
    Q_INVOKABLE void startCalibration();

  signals:
    void hostChanged();
    void portChanged();
    void cameraNamesChanged();
    void cameraIndexChanged();
    void backendModeChanged();
    void enableFilterChanged();
    void includeCustomParametersChanged();
    void includeARKitAliasesChanged();
    void includeACVABlendshapeParametersChanged();
    void mirrorPreviewChanged();
    void showCameraPreviewChanged();
    void flipLandmarkYChanged();
    void topLeftOriginChanged();
    void oneEuroParametersChanged();
    void statusChanged();
    void trackingStatsChanged();
    void calibrationStateChanged();

  private:
    void loadSettings();
    void saveSettings();
    void installCameraObservers();
    void removeCameraObservers();
    void reloadCameraDevices();
    void restartTrackingPipeline(bool resetCalibration);
    void applyOneEuroParameters(double minCutoff, double beta,
                                double derivativeCutoff);
    void stopVTSClient();
    void handlePipelineStatus(const QString& message, int status);

    std::unique_ptr<Impl> d;
};

#endif // VTS_SOURCE_QT_CONTROLLER_H
