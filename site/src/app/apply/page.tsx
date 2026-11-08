import {notFound, redirect} from "next/navigation";
import {getCurrentUser} from "@/lib/auth";
import { isPublicModuleEnabled } from "@/lib/modules";
export const metadata={title:"Вступление"};
export default async function ApplyPage(){
  if (!(await isPublicModuleEnabled("applications"))) notFound();
  const user=await getCurrentUser();
  redirect(user?"/app/application":"/login?next=%2Fapp%2Fapplication");
}
