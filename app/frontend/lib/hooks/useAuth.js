import { useContext } from 'react';
import AuthContext from '@/lib/providers/AuthProvider';

export default function useAuth() {
  return useContext(AuthContext);
}
export { useAuth };