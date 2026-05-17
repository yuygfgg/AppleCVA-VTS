#include "preview_item.h"

#include <QFont>
#include <QFontMetricsF>
#include <QPainter>
#include <QPainterPath>
#include <QtMath>

#include <cmath>
#include <cstring>
#include <limits>

struct LandmarkEdge {
    uint16_t a;
    uint16_t b;
};

static const LandmarkEdge kLandmarkEdges[] = {
    {0, 2},   {2, 3},   {3, 1},   {1, 5},   {5, 4},   {4, 0},   {0, 6},
    {1, 6},   {7, 9},   {9, 10},  {10, 8},  {8, 12},  {12, 11}, {11, 7},
    {7, 13},  {8, 13},  {14, 15}, {15, 16}, {17, 18}, {18, 19}, {20, 21},
    {21, 22}, {22, 23}, {23, 24}, {24, 25}, {25, 26}, {26, 27}, {27, 28},
    {28, 29}, {29, 30}, {30, 31}, {31, 32}, {32, 33}, {33, 20}, {34, 36},
    {36, 38}, {38, 35}, {35, 39}, {39, 37}, {37, 34}, {40, 41}, {41, 42},
    {42, 43}, {44, 45}, {45, 46}, {46, 47}, {47, 48}, {49, 51}, {50, 52},
    {53, 54}, {54, 55}, {55, 56}, {56, 57}, {57, 58}, {58, 59}, {59, 65},
    {65, 64}, {64, 63}, {63, 62}, {62, 61}, {61, 60},
};

VTSPreviewItem::VTSPreviewItem(QQuickItem* parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
}

bool VTSPreviewItem::mirrorPreview() const { return mirrorPreview_; }

void VTSPreviewItem::setMirrorPreview(bool enabled) {
    if (mirrorPreview_ == enabled) {
        return;
    }
    mirrorPreview_ = enabled;
    update();
    emit mirrorPreviewChanged();
}

bool VTSPreviewItem::showCameraPreview() const { return showCameraPreview_; }

void VTSPreviewItem::setShowCameraPreview(bool enabled) {
    if (showCameraPreview_ == enabled) {
        return;
    }
    showCameraPreview_ = enabled;
    update();
    emit showCameraPreviewChanged();
}

bool VTSPreviewItem::flipLandmarkY() const { return flipLandmarkY_; }

void VTSPreviewItem::setFlipLandmarkY(bool enabled) {
    if (flipLandmarkY_ == enabled) {
        return;
    }
    flipLandmarkY_ = enabled;
    update();
    emit flipLandmarkYChanged();
}

bool VTSPreviewItem::topLeftOrigin() const { return topLeftOrigin_; }

void VTSPreviewItem::setTopLeftOrigin(bool enabled) {
    if (topLeftOrigin_ == enabled) {
        return;
    }
    topLeftOrigin_ = enabled;
    update();
    emit topLeftOriginChanged();
}

void VTSPreviewItem::setFrame(const QImage& image,
                              const AppleCVATrackedFace* face, bool hasFace,
                              size_t detectedFaceCount, size_t trackedFaceCount,
                              int32_t lastStatus, double fps) {
    image_ = image;
    std::memset(&face_, 0, sizeof(face_));
    if (face != nullptr) {
        face_ = *face;
    }
    hasFace_ = hasFace;
    detectedFaceCount_ = detectedFaceCount;
    trackedFaceCount_ = trackedFaceCount;
    lastStatus_ = lastStatus;
    fps_ = fps;
    update();
}

void VTSPreviewItem::paint(QPainter* painter) {
    const QRectF bounds = boundingRect();
    painter->fillRect(bounds, QColor(12, 12, 16));

    const QRectF imageRect =
        image_.isNull() ? bounds : aspectFitRect(image_.size(), bounds);
    if (!image_.isNull() && showCameraPreview_) {
        painter->save();
        painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
        if (mirrorPreview_) {
            painter->translate(imageRect.right(), imageRect.top());
            painter->scale(-1.0, 1.0);
            painter->drawImage(
                QRectF(0.0, 0.0, imageRect.width(), imageRect.height()),
                image_);
        } else {
            painter->drawImage(imageRect, image_);
        }
        painter->restore();
    } else {
        QLinearGradient gradient(bounds.topLeft(), bounds.bottomRight());
        gradient.setColorAt(0.0, QColor(30, 32, 42));
        gradient.setColorAt(1.0, QColor(10, 12, 20));
        painter->fillRect(bounds, gradient);
    }

    if (!image_.isNull() && hasFace_) {
        drawFaceOverlay(painter, imageRect, static_cast<size_t>(image_.width()),
                        static_cast<size_t>(image_.height()));
    }
    drawStatusOverlay(painter);
}

QRectF VTSPreviewItem::aspectFitRect(const QSizeF& sourceSize,
                                     const QRectF& bounds) const {
    if (sourceSize.width() <= 0.0 || sourceSize.height() <= 0.0 ||
        bounds.width() <= 0.0 || bounds.height() <= 0.0) {
        return bounds;
    }
    const qreal sourceAspect = sourceSize.width() / sourceSize.height();
    const qreal boundsAspect = bounds.width() / bounds.height();
    QRectF rect = bounds;
    if (boundsAspect > sourceAspect) {
        rect.setWidth(bounds.height() * sourceAspect);
        rect.moveLeft(bounds.left() + (bounds.width() - rect.width()) * 0.5);
    } else {
        rect.setHeight(bounds.width() / sourceAspect);
        rect.moveTop(bounds.top() + (bounds.height() - rect.height()) * 0.5);
    }
    return rect;
}

QPointF VTSPreviewItem::pointForImagePoint(float x, float y, size_t imageWidth,
                                           size_t imageHeight,
                                           const QRectF& imageRect) const {
    if (!topLeftOrigin_) {
        y = static_cast<float>(imageHeight) - y;
    }
    if (mirrorPreview_) {
        x = static_cast<float>(imageWidth) - x;
    }
    const qreal scaleX = imageRect.width() / static_cast<qreal>(imageWidth);
    const qreal scaleY = imageRect.height() / static_cast<qreal>(imageHeight);
    return QPointF(imageRect.left() + static_cast<qreal>(x) * scaleX,
                   imageRect.top() + static_cast<qreal>(y) * scaleY);
}

QRectF
VTSPreviewItem::rectForNormalizedFaceRect(const float rect[4],
                                          const QRectF& imageRect) const {
    qreal sourceX = static_cast<qreal>(rect[0]);
    qreal sourceY = static_cast<qreal>(rect[1]);
    if (!topLeftOrigin_) {
        sourceY = 1.0 - sourceY - static_cast<qreal>(rect[3]);
    }
    if (mirrorPreview_) {
        sourceX = 1.0 - sourceX - static_cast<qreal>(rect[2]);
    }
    return QRectF(imageRect.left() + sourceX * imageRect.width(),
                  imageRect.top() + sourceY * imageRect.height(),
                  static_cast<qreal>(rect[2]) * imageRect.width(),
                  static_cast<qreal>(rect[3]) * imageRect.height());
}

bool VTSPreviewItem::landmarkBoundsForFace(const AppleCVATrackedFace& face,
                                           const QRectF& imageRect,
                                           size_t imageWidth,
                                           size_t imageHeight,
                                           QRectF* outRect) const {
    if (outRect == nullptr || face.landmark_pair_count == 0) {
        return false;
    }

    qreal minX = std::numeric_limits<qreal>::max();
    qreal minY = std::numeric_limits<qreal>::max();
    qreal maxX = -std::numeric_limits<qreal>::max();
    qreal maxY = -std::numeric_limits<qreal>::max();
    size_t validCount = 0;
    for (size_t i = 0; i < face.landmark_pair_count; ++i) {
        const size_t base = i * 2;
        if (base + 1 >= face.landmark_float_count ||
            base + 1 >= APPLECVA_MAX_LANDMARK_FLOATS) {
            continue;
        }
        const float x = face.landmarks[base];
        const float y = face.landmarks[base + 1];
        if (!std::isfinite(x) || !std::isfinite(y)) {
            continue;
        }
        const QPointF point =
            pointForImagePoint(x, y, imageWidth, imageHeight, imageRect);
        minX = qMin(minX, point.x());
        minY = qMin(minY, point.y());
        maxX = qMax(maxX, point.x());
        maxY = qMax(maxY, point.y());
        ++validCount;
    }

    if (validCount < 6 || maxX <= minX || maxY <= minY) {
        return false;
    }

    const qreal padX = qMax(18.0, (maxX - minX) * 0.16);
    const qreal padY = qMax(18.0, (maxY - minY) * 0.22);
    minX = qMax(imageRect.left(), minX - padX);
    minY = qMax(imageRect.top(), minY - padY);
    maxX = qMin(imageRect.right(), maxX + padX);
    maxY = qMin(imageRect.bottom(), maxY + padY);
    *outRect = QRectF(QPointF(minX, minY), QPointF(maxX, maxY));
    return true;
}

QPointF VTSPreviewItem::landmarkPoint(float x, float y, const QRectF& imageRect,
                                      size_t imageWidth, size_t imageHeight,
                                      const QRectF& landmarkBounds,
                                      bool hasLandmarkBounds) const {
    QPointF point =
        pointForImagePoint(x, y, imageWidth, imageHeight, imageRect);
    if (flipLandmarkY_ && hasLandmarkBounds) {
        point.setY(landmarkBounds.top() + landmarkBounds.bottom() - point.y());
    }
    return point;
}

void VTSPreviewItem::drawFaceOverlay(QPainter* painter, const QRectF& imageRect,
                                     size_t imageWidth, size_t imageHeight) {
    QRectF landmarkBounds;
    const bool hasLandmarkBounds = landmarkBoundsForFace(
        face_, imageRect, imageWidth, imageHeight, &landmarkBounds);

    QRectF faceBounds;
    if (face_.rect[2] > 0.0f && face_.rect[3] > 0.0f) {
        faceBounds = rectForNormalizedFaceRect(face_.rect, imageRect);
    } else if (hasLandmarkBounds) {
        faceBounds = landmarkBounds;
    }
    if (!faceBounds.isEmpty()) {
        painter->save();
        painter->setPen(QPen(QColor(255, 184, 46, 230), 2.0));
        painter->setBrush(Qt::NoBrush);
        painter->drawRoundedRect(faceBounds, 6.0, 6.0);
        painter->restore();
    }

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);
    QPainterPath lines;
    for (const LandmarkEdge& edge : kLandmarkEdges) {
        if (edge.a >= face_.landmark_pair_count ||
            edge.b >= face_.landmark_pair_count) {
            continue;
        }
        const size_t aBase = static_cast<size_t>(edge.a) * 2;
        const size_t bBase = static_cast<size_t>(edge.b) * 2;
        if (aBase + 1 >= face_.landmark_float_count ||
            bBase + 1 >= face_.landmark_float_count) {
            continue;
        }
        const QPointF a = landmarkPoint(
            face_.landmarks[aBase], face_.landmarks[aBase + 1], imageRect,
            imageWidth, imageHeight, landmarkBounds, hasLandmarkBounds);
        const QPointF b = landmarkPoint(
            face_.landmarks[bBase], face_.landmarks[bBase + 1], imageRect,
            imageWidth, imageHeight, landmarkBounds, hasLandmarkBounds);
        lines.moveTo(a);
        lines.lineTo(b);
    }
    painter->setPen(QPen(QColor(26, 255, 140, 230), 1.6));
    painter->drawPath(lines);

    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor(140, 230, 255, 245));
    for (size_t i = 0; i < face_.landmark_pair_count; ++i) {
        const size_t base = i * 2;
        if (base + 1 >= face_.landmark_float_count) {
            continue;
        }
        const QPointF point = landmarkPoint(
            face_.landmarks[base], face_.landmarks[base + 1], imageRect,
            imageWidth, imageHeight, landmarkBounds, hasLandmarkBounds);
        painter->drawEllipse(point, 2.4, 2.4);
    }
    painter->restore();
}

void VTSPreviewItem::drawStatusOverlay(QPainter* painter) {
    QString text = QStringLiteral("%1 FPS  detected %2  tracked %3")
                       .arg(fps_, 0, 'f', 1)
                       .arg(detectedFaceCount_)
                       .arg(trackedFaceCount_);
    if (hasFace_) {
        text +=
            QStringLiteral("  confidence %1").arg(face_.confidence, 0, 'f', 3);
    }
    if (lastStatus_ != APPLECVA_OK) {
        text += QStringLiteral("\nstatus %1 (%2)")
                    .arg(QString::fromUtf8(AppleCVAStatusString(lastStatus_)))
                    .arg(lastStatus_);
    }

    QFont font = painter->font();
    font.setFamily(QStringLiteral("Menlo"));
    font.setPointSizeF(12.0);
    painter->setFont(font);

    const QFontMetricsF metrics(font);
    const QRectF textRect = metrics.boundingRect(
        QRectF(0, 0, width() - 32.0, height()),
        Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap, text);
    const QRectF box(14.0, 14.0, textRect.width() + 18.0,
                     textRect.height() + 12.0);
    painter->save();
    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor(0, 0, 0, 150));
    painter->drawRoundedRect(box, 6.0, 6.0);
    painter->setPen(QColor(255, 255, 255));
    painter->drawText(box.adjusted(9.0, 6.0, -9.0, -6.0),
                      Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap, text);
    painter->restore();
}
