& "C:\Program Files\Android\Android Studio\jbr\bin\java.exe" -version
& "C:\Users\月笙如歌\AppData\Local\Android\Sdk\platform-tools\adb.exe" --version
$env:Path -split ";" | Select-String -Pattern "Android|java" -CaseSensitive:$false
