#include "controller.h"
#include "preview_item.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("AppleCVA VTS Source"));
    QCoreApplication::setOrganizationName(QStringLiteral("AppleCVA"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    qmlRegisterType<VTSPreviewItem>("AppleCVANative", 1, 0, "VTSPreview");

    VTSController controller;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("controller"),
                                             &controller);
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("AppleCVAVTSSource"),
                          QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    QMetaObject::invokeMethod(&controller, "start", Qt::QueuedConnection);
    return app.exec();
}
