export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      achievements: {
        Row: {
          description: string
          goal: number
          id: string
          key: string
          name: string
          reward: number
          sort_order: number
        }
        Insert: {
          description: string
          goal?: number
          id?: string
          key: string
          name: string
          reward: number
          sort_order?: number
        }
        Update: {
          description?: string
          goal?: number
          id?: string
          key?: string
          name?: string
          reward?: number
          sort_order?: number
        }
        Relationships: []
      }
      code_redemptions: {
        Row: {
          code_id: string
          created_at: string
          id: string
          user_id: string
        }
        Insert: {
          code_id: string
          created_at?: string
          id?: string
          user_id: string
        }
        Update: {
          code_id?: string
          created_at?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "code_redemptions_code_id_fkey"
            columns: ["code_id"]
            isOneToOne: false
            referencedRelation: "promo_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "code_redemptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory: {
        Row: {
          created_at: string
          id: string
          item_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          item_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          item_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "shop_items"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          content: string
          created_at: string
          deleted: boolean
          id: string
          room_id: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          deleted?: boolean
          id?: string
          room_id: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          deleted?: boolean
          id?: string
          room_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_user_id_profiles_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          banned: boolean
          coins: number
          created_at: string
          font_key: string
          id: string
          last_claim_at: string | null
          level: number
          muted_until: string | null
          name_color: string
          streak: number
          username: string
          vip_tier: string | null
          xp: number
        }
        Insert: {
          banned?: boolean
          coins?: number
          created_at?: string
          font_key?: string
          id: string
          last_claim_at?: string | null
          level?: number
          muted_until?: string | null
          name_color?: string
          streak?: number
          username: string
          vip_tier?: string | null
          xp?: number
        }
        Update: {
          banned?: boolean
          coins?: number
          created_at?: string
          font_key?: string
          id?: string
          last_claim_at?: string | null
          level?: number
          muted_until?: string | null
          name_color?: string
          streak?: number
          username?: string
          vip_tier?: string | null
          xp?: number
        }
        Relationships: []
      }
      promo_codes: {
        Row: {
          active: boolean
          code: string
          id: string
          note: string
          reward: number
        }
        Insert: {
          active?: boolean
          code: string
          id?: string
          note?: string
          reward: number
        }
        Update: {
          active?: boolean
          code?: string
          id?: string
          note?: string
          reward?: number
        }
        Relationships: []
      }
      rooms: {
        Row: {
          id: string
          mod_only: boolean
          name: string
          slug: string
          sort_order: number
        }
        Insert: {
          id?: string
          mod_only?: boolean
          name: string
          slug: string
          sort_order?: number
        }
        Update: {
          id?: string
          mod_only?: boolean
          name?: string
          slug?: string
          sort_order?: number
        }
        Relationships: []
      }
      shop_items: {
        Row: {
          id: string
          key: string
          kind: string
          name: string
          price: number
          rarity: string
          sort_order: number
          value: string
        }
        Insert: {
          id?: string
          key: string
          kind: string
          name: string
          price: number
          rarity: string
          sort_order?: number
          value: string
        }
        Update: {
          id?: string
          key?: string
          kind?: string
          name?: string
          price?: number
          rarity?: string
          sort_order?: number
          value?: string
        }
        Relationships: []
      }
      user_achievements: {
        Row: {
          achievement_id: string
          claimed: boolean
          id: string
          progress: number
          user_id: string
        }
        Insert: {
          achievement_id: string
          claimed?: boolean
          id?: string
          progress?: number
          user_id: string
        }
        Update: {
          achievement_id?: string
          claimed?: boolean
          id?: string
          progress?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_achievements_achievement_id_fkey"
            columns: ["achievement_id"]
            isOneToOne: false
            referencedRelation: "achievements"
            referencedColumns: ["id"]
          },
        ]
      }
      user_credentials: {
        Row: {
          created_at: string
          password_hash: string
          user_id: string
        }
        Insert: {
          created_at?: string
          password_hash: string
          user_id: string
        }
        Update: {
          created_at?: string
          password_hash?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_credentials_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      user_stats: {
        Row: {
          flips_won: number
          messages_sent: number
          user_id: string
        }
        Insert: {
          flips_won?: number
          messages_sent?: number
          user_id: string
        }
        Update: {
          flips_won?: number
          messages_sent?: number
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      bump_progress: {
        Args: { _amount: number; _key: string; _user: string }
        Returns: undefined
      }
      buy_item: { Args: { _item: string; _user: string }; Returns: Json }
      claim_achievement: {
        Args: { _achievement: string; _user: string }
        Returns: Json
      }
      claim_daily: { Args: { _user: string }; Returns: Json }
      claim_mod: { Args: { _code: string; _user: string }; Returns: undefined }
      create_guest: {
        Args: { _username: string }
        Returns: {
          banned: boolean
          coins: number
          created_at: string
          font_key: string
          id: string
          last_claim_at: string | null
          level: number
          muted_until: string | null
          name_color: string
          streak: number
          username: string
          vip_tier: string | null
          xp: number
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_message: {
        Args: { _actor: string; _message: string }
        Returns: undefined
      }
      game_settle: {
        Args: { _bet: number; _payout: number; _user: string; _won: boolean }
        Returns: number
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      login_user: {
        Args: { _password: string; _username: string }
        Returns: {
          banned: boolean
          coins: number
          created_at: string
          font_key: string
          id: string
          last_claim_at: string | null
          level: number
          muted_until: string | null
          name_color: string
          streak: number
          username: string
          vip_tier: string | null
          xp: number
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mod_action: {
        Args: {
          _action: string
          _actor: string
          _minutes?: number
          _target: string
        }
        Returns: undefined
      }
      mod_grant_coins: {
        Args: { _actor: string; _amount: number; _target: string }
        Returns: undefined
      }
      play_coin_flip: {
        Args: { _user: string; bet: number; guess: string }
        Returns: Json
      }
      play_dice: {
        Args: { _user: string; bet: number; pick: number }
        Returns: Json
      }
      play_hilo: {
        Args: { _user: string; bet: number; call: string }
        Returns: Json
      }
      play_rps: {
        Args: { _user: string; bet: number; pick: string }
        Returns: Json
      }
      play_slots: { Args: { _user: string; bet: number }; Returns: Json }
      redeem_code: { Args: { _code: string; _user: string }; Returns: Json }
      signup_user: {
        Args: { _password: string; _username: string }
        Returns: {
          banned: boolean
          coins: number
          created_at: string
          font_key: string
          id: string
          last_claim_at: string | null
          level: number
          muted_until: string | null
          name_color: string
          streak: number
          username: string
          vip_tier: string | null
          xp: number
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      vip_max_bet: { Args: { _tier: string }; Returns: number }
      vip_mult: { Args: { _tier: string }; Returns: number }
    }
    Enums: {
      app_role: "admin" | "mod" | "user"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "mod", "user"],
    },
  },
} as const
