export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      admin_catalog_resource_detail: {
        Args: { p_actor_id: string; p_id: string; p_resource: string }
        Returns: Json
      }
      admin_product_overview: {
        Args: { p_actor_id: string; p_product_id: string }
        Returns: Json
      }
      admin_query_catalog_resource: {
        Args: {
          p_actor_id: string
          p_cursor?: string
          p_direction?: string
          p_limit?: number
          p_resource: string
          p_search?: string
          p_sort?: string
          p_status?: string
        }
        Returns: Json
      }
      admin_query_resource: {
        Args: {
          p_actor_id: string
          p_cursor?: string
          p_direction?: string
          p_limit?: number
          p_resource: string
          p_search?: string
          p_sort?: string
          p_status?: string
        }
        Returns: Json
      }
      check_access: {
        Args: { p_app_slug: string; p_feature_code: string; p_user_id: string }
        Returns: {
          allowed: boolean
          decision_id: string
          expires_at: string
          feature: string
          source_product: string
          value: Json
        }[]
      }
      create_feedback: {
        Args: {
          p_app_slug: string
          p_content: string
          p_kind: string
          p_title: string
          p_user_id: string
        }
        Returns: {
          created_at: string
          id: string
          status: string
        }[]
      }
      create_platform_session: {
        Args: {
          p_csrf_hash: string
          p_expires_at: string
          p_token_hash: string
          p_user_id: string
        }
        Returns: {
          expires_at: string
          session_id: string
        }[]
      }
      current_profile: {
        Args: never
        Returns: {
          avatar_url: string
          created_at: string
          display_name: string
          id: string
          locale: string
          status: string
          updated_at: string
        }[]
      }
      get_admin_session: {
        Args: { p_token_hash: string }
        Returns: {
          aal: string
          display_name: string
          expires_at: string
          mfa_state: string
          role: string
          user_id: string
        }[]
      }
      get_platform_session: {
        Args: { p_token_hash: string }
        Returns: {
          avatar_url: string
          display_name: string
          expires_at: string
          locale: string
          profile_status: string
          session_id: string
          user_id: string
        }[]
      }
      get_public_app: {
        Args: { app_slug: string }
        Returns: {
          category: string
          name: string
          slug: string
          status: string
        }[]
      }
      get_public_products: {
        Args: never
        Returns: {
          billing_type: string
          name: string
          sku: string
          version: number
        }[]
      }
      grant_entitlement: {
        Args: {
          p_actor_id?: string
          p_actor_type?: string
          p_expires_at?: string
          p_product_version_id: string
          p_reason?: string
          p_request_id?: string
          p_restores_grant_id?: string
          p_source_id?: string
          p_source_type: string
          p_starts_at?: string
          p_user_id: string
        }
        Returns: {
          audit_log_id: string
          expires_at: string
          grant_id: string
          source_id: string
          starts_at: string
          status: string
        }[]
      }
      list_user_entitlements: {
        Args: { p_user_id: string }
        Returns: {
          expires_at: string
          feature: string
          source_product: string
          value: Json
        }[]
      }
      publish_product_version: {
        Args: { p_product_version_id: string }
        Returns: {
          product_version_id: string
          published_at: string
          status: string
        }[]
      }
      redeem_code: {
        Args: {
          p_code_hash: string
          p_idempotency_key: string
          p_ip_hash?: string
          p_request_hash: string
          p_user_id: string
        }
        Returns: {
          batch_id: string
          code_id: string
          grant_id: string
          idempotency_record_id: string
          redeemed_at: string
          redemption_id: string
          status: string
        }[]
      }
      resolve_app_origin: {
        Args: { p_origin: string }
        Returns: {
          app_slug: string
          environment: string
        }[]
      }
      restore_entitlement: {
        Args: {
          p_actor_id: string
          p_grant_id: string
          p_reason: string
          p_request_id?: string
        }
        Returns: {
          audit_log_id: string
          expires_at: string
          grant_id: string
          source_id: string
          starts_at: string
          status: string
        }[]
      }
      retire_product_version: {
        Args: { p_product_version_id: string }
        Returns: {
          product_version_id: string
          status: string
        }[]
      }
      revoke_all_platform_sessions: {
        Args: { p_reason: string; p_user_id: string }
        Returns: number
      }
      revoke_entitlement: {
        Args: {
          p_actor_id: string
          p_actor_type: string
          p_grant_id: string
          p_reason: string
          p_request_id?: string
        }
        Returns: {
          audit_log_id: string
          grant_id: string
          revoked_at: string
          status: string
        }[]
      }
      revoke_platform_session: {
        Args: { p_reason?: string; p_token_hash: string }
        Returns: {
          revoked: boolean
        }[]
      }
      rotate_platform_csrf: {
        Args: { p_csrf_hash: string; p_token_hash: string }
        Returns: {
          issued: boolean
        }[]
      }
      set_current_product_version: {
        Args: { p_product_id: string; p_product_version_id: string }
        Returns: {
          current_version_id: string
          product_id: string
        }[]
      }
      verify_platform_csrf: {
        Args: { p_csrf_hash: string; p_token_hash: string }
        Returns: {
          valid: boolean
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

