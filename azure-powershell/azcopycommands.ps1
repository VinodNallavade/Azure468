azcopy --version

azcopy login

azcopy make "https://azstreastus001.privatelink.blob.core.windows.net/powershellscripts-002"


azcopy copy "D:\PersonnelWork\Azure468\Azure468\azure-powershell\*" "https://azstreastus001.blob.core.windows.net/powershellscripts?sv=2026-02-06&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-10-28T10:23:07Z&st=2026-10-28T02:08:07Z&spr=https&sig=bwAsFx31lhOk9cLeXyU5mIWSPeUENP%2FWIphiwRMZZVg%3D" --include-pattern '*.ps1'


azcopy copy "C:\Users\vinod\Pictures\Screenshots\Screenshot 2026-10-27 072332.png" "https://azstreastus001.blob.core.windows.net/invoices-new/lifecycle.png?sv=2026-02-06&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-10-28T10:23:07Z&st=2026-10-28T02:08:07Z&spr=https&sig=bwAsFx31lhOk9cLeXyU5mIWSPeUENP%2FWIphiwRMZZVg%3D"


azcopy copy "https://azstreastus001.blob.core.windows.net/invoices-new?sv=2026-02-06&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-10-28T10:23:07Z&st=2026-10-28T02:08:07Z&spr=https&sig=bwAsFx31lhOk9cLeXyU5mIWSPeUENP%2FWIphiwRMZZVg%3D" '"https://azstreastus001.blob.core.windows.net/mycontainer1234?sv=2026-02-06&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2026-10-28T10:23:07Z&st=2026-10-28T02:08:07Z&spr=https&sig=bwAsFx31lhOk9cLeXyU5mIWSPeUENP%2FWIphiwRMZZVg%3D"' --recursive