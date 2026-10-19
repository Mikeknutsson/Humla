import {redirect} from "next/navigation";
// Legacy address retained only for existing bookmarks. The UI lives in Dashboard.
export default function LegacyRedirect(){redirect("/kpi/ekonomi");}
