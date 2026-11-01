# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Usage', type: :request do
  let(:family) do
    Family.create!(
      name: 'Usage Docs Family',
      currency: 'USD',
      locale: 'en',
      date_format: '%m-%d-%Y'
    )
  end

  let(:user) do
    family.users.create!(
      email: 'usage-docs@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Ada',
      last_name: 'Lovelace'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'Usage Docs Key',
      key: key,
      scopes: %w[read],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  path '/api/v1/usage' do
    get 'Retrieve API key usage' do
      tags 'Usage'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'usage returned' do
        schema '$ref' => '#/components/schemas/Usage'

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end
    end
  end
end
