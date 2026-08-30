import { AuthorizationsWorkspace } from "./_components/authorizations-workspace";
import { authorizations } from "./_components/data";

export default function Page() {
  return <AuthorizationsWorkspace authorizations={authorizations} />;
}
