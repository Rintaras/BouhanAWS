import { useState, useEffect } from 'react';

interface AuthState {
    token: string | null;
    isAuthenticated: boolean;
    loading: boolean;
}

interface LoginResponse {
    token: string;
}

export const useAuth = () => {
    const [authState, setAuthState] = useState<AuthState>({
        token: localStorage.getItem('auth_token'),
        isAuthenticated: !!localStorage.getItem('auth_token'),
        loading: false
    });

    const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:3000';

    const login = async (username: string, password: string): Promise<string> => {
        setAuthState(prev => ({ ...prev, loading: true }));

        try {
            const response = await fetch(`${API_BASE_URL}/auth/login`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ username, password }),
            });

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.error || 'ログインに失敗しました');
            }

            const data: LoginResponse = await response.json();

            localStorage.setItem('auth_token', data.token);
            setAuthState({
                token: data.token,
                isAuthenticated: true,
                loading: false
            });

            return data.token;
        } catch (error) {
            setAuthState(prev => ({ ...prev, loading: false }));
            throw error;
        }
    };

    const logout = () => {
        localStorage.removeItem('auth_token');
        setAuthState({
            token: null,
            isAuthenticated: false,
            loading: false
        });
    };

    const getAuthHeaders = () => {
        if (!authState.token) {
            return {};
        }
        return {
            'Authorization': `Bearer ${authState.token}`
        };
    };

    const isTokenExpired = (token: string): boolean => {
        try {
            const payload = JSON.parse(atob(token.split('.')[1]));
            const currentTime = Date.now() / 1000;
            return payload.exp < currentTime;
        } catch {
            return true;
        }
    };

    useEffect(() => {
        const token = localStorage.getItem('auth_token');
        if (token && isTokenExpired(token)) {
            logout();
        }
    }, []);

    return {
        ...authState,
        login,
        logout,
        getAuthHeaders
    };
}; 