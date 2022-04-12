# frozen_string_literal: true

module Types
  module BillableMetrics
    class Object < Types::BaseObject
      graphql_name 'BillableMetric'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: false
      field :description, String
      field :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :can_be_deleted, Boolean, null: false do
        description 'Check if billable metric is deletable'
      end

      def can_be_deleted
        object.deletable?
      end
    end
  end
end
