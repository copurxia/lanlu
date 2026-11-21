export type RpcSelectOption = {
  index: number
  label: string
  description?: string
  cover?: string
}

export type RpcSelectRequest = {
  request_id: string
  title: string
  message?: string
  default_index?: number
  timeout_seconds?: number
  options: RpcSelectOption[]
}
