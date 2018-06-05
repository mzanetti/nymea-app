include(mea.pri)

TEMPLATE=subdirs

SUBDIRS = libnymea-common libmea-core mea
libmea-core.depends = libnymea-common
mea.depends = libmea-core

withtests: {
    SUBDIRS += tests
    tests.depends = libmea-core
}

# Building a Windows installer:
# Install Visual Studio, Qt and NSIS on Windows. Make sure NSIS is in your path.
# Use QtCreator to create a release build, make sure to *disable* shadow build.
# After building, run "make wininstaller"
wininstaller.depends = mea
equals(BRANDING, "") {
    APP_NAME = mea
    PACKAGE_DIR = $$shell_path($$PWD)\packaging\windows
    PACKAGE_NAME = mea-win-installer
} else {
    APP_NAME = $${BRANDING}
    PACKAGE_NAME = $${BRANDING}-win-installer
    PACKAGE_DIR = $$shell_path($$PWD)\packaging\windows_$${APP_NAME}
}
OLDSTRING="<Version>.*</Version>"
NEWSTRING="<Version>$${MEA_VERSION}</Version>"
wininstaller.commands += @powershell -Command \"(gc $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\meta\package.xml) -replace \'$${OLDSTRING}\',\'$${NEWSTRING}\' | sc $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\meta\package.xml\" &&
wininstaller.commands += rmdir /S /Q $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data & mkdir $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data &&
wininstaller.commands += copy $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\meta\logo.ico $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data\logo.ico &&
CONFIG(debug,debug|release):wininstaller.commands += copy mea\debug\mea.exe $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data\\$${APP_NAME}.exe &&
CONFIG(release,debug|release):wininstaller.commands += copy mea\release\mea.exe $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data\\$${APP_NAME}.exe &&
!equals(SSL_LIBS, "") {
message("Deploying SSL libs from $${SSL_LIBS} to package.")
wininstaller.commands += copy $${SSL_LIBS}\libeay32.dll $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data &&
wininstaller.commands += copy $${SSL_LIBS}\ssleay32.dll $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data &&
}
wininstaller.commands += windeployqt --compiler-runtime --qmldir \"$${top_srcdir}\"\mea\ui $${PACKAGE_DIR}\packages\io.guh.$${APP_NAME}\data\ &&
wininstaller.commands += binarycreator -c $${PACKAGE_DIR}\config\config.xml -p $${PACKAGE_DIR}\packages\ $${PACKAGE_NAME}
message("cmd: $${wininstaller.commands}")
QMAKE_EXTRA_TARGETS += wininstaller

TRANSLATIONS += $$files(mea/translations/*.ts, true)
lrelease.commands = lrelease $$_FILE_
lrelease-qmake_all.commands = lrelease $$_FILE_
QMAKE_EXTRA_TARGETS += lrelease lrelease-make_first lrelease-qmake_all lrelease-install_subtargets

mea.depends += lrelease