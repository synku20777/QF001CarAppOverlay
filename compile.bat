@echo off

echo =========================================================                                              
echo " CarAPP Overlay "
echo =========================================================

echo You must have Java installed on your computer (JDK and JRE)
echo If you do not have it installed, please install it before
echo running this program.

pause

echo Compiling overlay...
"%cd%\.compiler\aapt.exe" p -S "%cd%\resources\res" -M "%cd%\.compiler\manifest\AndroidManifest.xml" -I "%cd%\.compiler\framework-res.apk" -F carappoverlay.apk -f

echo Signing overlay APK...
if not defined JAVA_HOME if exist "%cd%\.compiler\jre" set "JAVA_HOME=%cd%\.compiler\jre"
"%cd%\.compiler\apksigner.bat" sign --ks "%cd%\.compiler\overlaysig.jks" --ks-pass pass:nicholaschum --key-pass pass:nicholaschum carappoverlay.apk