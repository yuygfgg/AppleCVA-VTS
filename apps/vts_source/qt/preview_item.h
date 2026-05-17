#ifndef VTS_SOURCE_QT_PREVIEW_ITEM_H
#define VTS_SOURCE_QT_PREVIEW_ITEM_H

#include "applecva.h"

#include <QImage>
#include <QQuickPaintedItem>

class VTSPreviewItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(bool mirrorPreview READ mirrorPreview WRITE setMirrorPreview
                   NOTIFY mirrorPreviewChanged)
    Q_PROPERTY(bool showCameraPreview READ showCameraPreview WRITE
                   setShowCameraPreview NOTIFY showCameraPreviewChanged)
    Q_PROPERTY(bool flipLandmarkY READ flipLandmarkY WRITE setFlipLandmarkY
                   NOTIFY flipLandmarkYChanged)
    Q_PROPERTY(bool topLeftOrigin READ topLeftOrigin WRITE setTopLeftOrigin
                   NOTIFY topLeftOriginChanged)

  public:
    explicit VTSPreviewItem(QQuickItem* parent = nullptr);

    bool mirrorPreview() const;
    void setMirrorPreview(bool enabled);

    bool showCameraPreview() const;
    void setShowCameraPreview(bool enabled);

    bool flipLandmarkY() const;
    void setFlipLandmarkY(bool enabled);

    bool topLeftOrigin() const;
    void setTopLeftOrigin(bool enabled);

    void setFrame(const QImage& image, const AppleCVATrackedFace* face,
                  bool hasFace, size_t detectedFaceCount,
                  size_t trackedFaceCount, int32_t lastStatus, double fps);

    void paint(QPainter* painter) override;

  signals:
    void mirrorPreviewChanged();
    void showCameraPreviewChanged();
    void flipLandmarkYChanged();
    void topLeftOriginChanged();

  private:
    QRectF aspectFitRect(const QSizeF& sourceSize, const QRectF& bounds) const;
    QPointF pointForImagePoint(float x, float y, size_t imageWidth,
                               size_t imageHeight,
                               const QRectF& imageRect) const;
    QRectF rectForNormalizedFaceRect(const float rect[4],
                                     const QRectF& imageRect) const;
    bool landmarkBoundsForFace(const AppleCVATrackedFace& face,
                               const QRectF& imageRect, size_t imageWidth,
                               size_t imageHeight, QRectF* outRect) const;
    QPointF landmarkPoint(float x, float y, const QRectF& imageRect,
                          size_t imageWidth, size_t imageHeight,
                          const QRectF& landmarkBounds,
                          bool hasLandmarkBounds) const;
    void drawFaceOverlay(QPainter* painter, const QRectF& imageRect,
                         size_t imageWidth, size_t imageHeight);
    void drawStatusOverlay(QPainter* painter);

    QImage image_;
    AppleCVATrackedFace face_{};
    bool hasFace_ = false;
    size_t detectedFaceCount_ = 0;
    size_t trackedFaceCount_ = 0;
    int32_t lastStatus_ = APPLECVA_OK;
    double fps_ = 0.0;
    bool mirrorPreview_ = true;
    bool showCameraPreview_ = true;
    bool flipLandmarkY_ = false;
    bool topLeftOrigin_ = true;
};

#endif // VTS_SOURCE_QT_PREVIEW_ITEM_H
