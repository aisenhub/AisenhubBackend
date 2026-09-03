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
      admin_catalog_command: {
        Args: {
          p_action: string
          p_actor_id: string
          p_idempotency_key?: string
          p_payload?: Json
          p_reason?: string
          p_request_hash?: string
          p_request_id?: string
          p_resource_id: string
        }
        Returns: Json
      }
      admin_catalog_draft_command: {
        Args: {
          p_action: string
          p_actor_id: string
          p_expected_updated_at?: string
          p_idempotency_key?: string
          p_parent_id?: string
          p_payload?: Json
          p_reason?: string
          p_request_hash?: string
          p_request_id?: string
          p_resource_id?: string
        }
        Returns: Json
      }
      admin_catalog_resource_detail: {
        Args: { p_actor_id: string; p_id: string; p_resource: string }
        Returns: Json
      }
      admin_customer_command: {
        Args: {
          p_action: string
          p_actor_id: string
          p_idempotency_key?: string
          p_payload?: Json
          p_reason?: string
          p_request_hash?: string
          p_request_id?: string
          p_resource_id: string
        }
        Returns: Json
      }
      admin_list_application_memberships: {
        Args: { p_actor_id: string; p_application_id: string }
        Returns: {
          activated_at: string
          application_id: string
          application_name: string
          application_slug: string
          created_source: string
          deleted_at: string
          id: string
          joined_at: string
          left_at: string
          membership_status: string
          suspended_at: string
          suspended_reason: string
          user_id: string
        }[]
      }
      admin_list_application_oauth_clients: {
        Args: { p_actor_id: string; p_application_id: string }
        Returns: {
          application_id: string
          client_type: string
          created_at: string
          environment: string
          external_client_id: string
          id: string
          name: string
          provider: string
          status: string
          updated_at: string
        }[]
      }
      admin_operations_overview: { Args: { p_actor_id: string }; Returns: Json }
      admin_order_overview: {
        Args: { p_actor_id: string; p_order_id: string }
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
      admin_query_commerce_resource: {
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
      admin_query_customer_resource: {
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
      admin_query_products: {
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
      admin_redemption_command: {
        Args: {
          p_action: string
          p_actor_id: string
          p_idempotency_key?: string
          p_payload?: Json
          p_reason?: string
          p_request_hash?: string
          p_request_id?: string
          p_resource_id?: string
        }
        Returns: Json
      }
      admin_refund_order_item: {
        Args: {
          p_actor_id: string
          p_amount: number
          p_idempotency_key: string
          p_mode: string
          p_order_item_id: string
          p_reason: string
          p_request_hash: string
          p_request_id: string
        }
        Returns: Json
      }
      admin_user_overview: {
        Args: { p_actor_id: string; p_user_id: string }
        Returns: Json
      }
      admin_verify_order: {
        Args: {
          p_actor_id: string
          p_amount: number
          p_currency: string
          p_idempotency_key: string
          p_order_id: string
          p_payment_reference: string
          p_reason: string
          p_request_hash: string
          p_request_id: string
        }
        Returns: Json
      }
      application_membership_command: {
        Args: {
          p_action: string
          p_actor_id: string
          p_application_id?: string
          p_created_source?: string
          p_idempotency_key?: string
          p_membership_id?: string
          p_reason?: string
          p_request_hash?: string
          p_request_id?: string
          p_user_id?: string
        }
        Returns: Json
      }
      cancel_account_deletion: {
        Args: { p_request_id?: string; p_user_id: string }
        Returns: {
          completed_at: string
          deletion_request_id: string
          execute_after: string
          requested_at: string
          status: string
        }[]
      }
      chargeback_order: {
        Args: { p_order_id: string; p_reason: string }
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
      claim_account_deletion_request: {
        Args: { p_worker_id: string }
        Returns: {
          attempt_count: number
          deletion_request_id: string
          execute_after: string
          processing_started_at: string
          status: string
          user_id: string
        }[]
      }
      complete_account_deletion_request: {
        Args: {
          p_deletion_request_id: string
          p_request_id?: string
          p_worker_id: string
        }
        Returns: Json
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
      fail_account_deletion_request: {
        Args: {
          p_error_code: string
          p_request_id: string
          p_worker_id: string
        }
        Returns: {
          attempt_count: number
          deletion_request_id: string
          last_error_code: string
          next_attempt_at: string
          status: string
        }[]
      }
      fulfill_paid_order: {
        Args: { p_payment_event_id: string }
        Returns: Json
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
      list_user_application_memberships: {
        Args: { p_user_id: string }
        Returns: {
          activated_at: string
          application_category: string
          application_id: string
          application_name: string
          application_slug: string
          application_status: string
          created_source: string
          default_locale: string
          deleted_at: string
          id: string
          joined_at: string
          left_at: string
          membership_policy: string
          membership_status: string
          registration_policy: string
          suspended_at: string
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
      receive_payment_webhook_event: {
        Args: {
          p_amount: number
          p_currency: string
          p_event_type: string
          p_external_event_id: string
          p_occurred_at: string
          p_order_id: string
          p_payload_summary: Json
          p_payment_id: string
          p_provider: string
        }
        Returns: Json
      }
      record_paid_after_cancelled_order: {
        Args: { p_payment_event_id: string; p_reason: string }
        Returns: Json
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
      refund_order_item: {
        Args: {
          p_amount: number
          p_mode: string
          p_order_item_id: string
          p_reason: string
        }
        Returns: Json
      }
      request_account_deletion: {
        Args: {
          p_idempotency_key: string
          p_request_hash: string
          p_request_id?: string
          p_user_id: string
        }
        Returns: {
          completed_at: string
          deletion_request_id: string
          execute_after: string
          requested_at: string
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
      resolve_application_context: {
        Args: { p_client_id: string; p_user_id: string }
        Returns: {
          application_id: string
          application_slug: string
          application_status: string
          client_id: string
          client_status: string
          membership_id: string
          membership_policy: string
          membership_status: string
          profile_status: string
          user_id: string
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
      run_retention_cleanup: {
        Args: {
          p_batch_size?: number
          p_dry_run?: boolean
          p_idempotency_response_before: string
          p_security_context_before: string
          p_session_expired_before: string
        }
        Returns: Json
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

