#!/usr/bin/env node

import http from 'node:http'
import { writeFileSync } from 'node:fs'

const host = process.env.FIXTURE_TRANSCRIPTION_HOST || '127.0.0.1'
const port = Number(process.env.FIXTURE_TRANSCRIPTION_PORT || '0')
const readyPath = process.env.FIXTURE_TRANSCRIPTION_READY_PATH || ''
const receiptPath = process.env.FIXTURE_TRANSCRIPTION_RECEIPT_PATH || ''
const expectedModel = process.env.FIXTURE_TRANSCRIPTION_MODEL || 'whisper-1'
const transcript = process.env.FIXTURE_TRANSCRIPTION_TEXT || 'the quick brown fox jumps over the lazy dog.'
const maxBodyBytes = Number(process.env.FIXTURE_TRANSCRIPTION_MAX_BODY_BYTES || `${10 * 1024 * 1024}`)

function sendJSON(response, status, value) {
  const body = JSON.stringify(value)
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body)
  })
  response.end(body)
}

function sendText(response, status, value) {
  response.writeHead(status, {
    'content-type': 'text/plain; charset=utf-8',
    'content-length': Buffer.byteLength(value)
  })
  response.end(value)
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let size = 0
    request.on('data', chunk => {
      size += chunk.length
      if (size > maxBodyBytes) {
        reject(new Error(`request body exceeded ${maxBodyBytes} bytes`))
        request.destroy()
        return
      }
      chunks.push(chunk)
    })
    request.on('end', () => resolve(Buffer.concat(chunks)))
    request.on('error', reject)
  })
}

function splitHeaderValue(value) {
  const values = []
  let current = ''
  let inQuote = false
  let escaped = false

  for (const character of value) {
    if (escaped) {
      current += character
      escaped = false
      continue
    }

    if (character === '\\' && inQuote) {
      current += character
      escaped = true
      continue
    }

    if (character === '"') {
      inQuote = !inQuote
      current += character
      continue
    }

    if (character === ';' && !inQuote) {
      values.push(current.trim())
      current = ''
      continue
    }

    current += character
  }

  values.push(current.trim())
  return values
}

function unquoteHeaderValue(value) {
  const trimmed = value.trim()
  if (!trimmed.startsWith('"') || !trimmed.endsWith('"')) return trimmed
  return trimmed
    .slice(1, -1)
    .replace(/\\(.)/g, '$1')
}

function parseHeaderValue(value) {
  const parts = splitHeaderValue(value)
  const parameters = {}

  for (const part of parts.slice(1)) {
    const equalsIndex = part.indexOf('=')
    if (equalsIndex === -1) continue
    const name = part.slice(0, equalsIndex).trim().toLowerCase()
    if (!name) continue
    parameters[name] = unquoteHeaderValue(part.slice(equalsIndex + 1))
  }

  return {
    value: String(parts[0] || '').trim().toLowerCase(),
    parameters
  }
}

function parseHeaders(headersText) {
  const headers = {}
  const lines = []

  for (const line of headersText.split('\r\n')) {
    if (/^[\t ]/.test(line) && lines.length > 0) {
      lines[lines.length - 1] += ` ${line.trim()}`
    } else {
      lines.push(line)
    }
  }

  for (const line of lines) {
    const colonIndex = line.indexOf(':')
    if (colonIndex === -1) continue
    const name = line.slice(0, colonIndex).trim().toLowerCase()
    const value = line.slice(colonIndex + 1).trim()
    if (name && !(name in headers)) {
      headers[name] = value
    }
  }

  return headers
}

function parseMultipartParts(bodyText, contentType) {
  const parsedContentType = parseHeaderValue(contentType)
  const boundary = parsedContentType.parameters.boundary || ''
  if (parsedContentType.value !== 'multipart/form-data' || !boundary) return []

  const delimiter = `--${boundary}`
  const parts = []
  let delimiterIndex = bodyText.indexOf(delimiter)

  while (delimiterIndex !== -1) {
    let partStart = delimiterIndex + delimiter.length
    if (bodyText.startsWith('--', partStart)) break
    if (bodyText.startsWith('\r\n', partStart)) {
      partStart += 2
    }

    const headerEnd = bodyText.indexOf('\r\n\r\n', partStart)
    if (headerEnd === -1) break

    const headersText = bodyText.slice(partStart, headerEnd)
    const bodyStart = headerEnd + 4
    const nextDelimiterIndex = bodyText.indexOf(`\r\n${delimiter}`, bodyStart)
    const bodyEnd = nextDelimiterIndex === -1 ? bodyText.length : nextDelimiterIndex
    const partBodyText = bodyText.slice(bodyStart, bodyEnd)
    const headers = parseHeaders(headersText)
    const contentDisposition = headers['content-disposition'] || ''
    const parsedDisposition = parseHeaderValue(contentDisposition)

    parts.push({
      headersText,
      bodyText: partBodyText,
      contentDisposition,
      contentType: headers['content-type'] || '',
      name: parsedDisposition.parameters.name || '',
      filename: parsedDisposition.parameters.filename || ''
    })

    if (nextDelimiterIndex === -1) break
    delimiterIndex = nextDelimiterIndex + 2
  }

  return parts
}

function valueForMultipartField(parts, fieldName) {
  const fieldPart = parts.find(part => part.name === fieldName && part.filename === '')
  return fieldPart ? fieldPart.bodyText.trim() : ''
}

function hasWAVContentType(contentType) {
  const mediaType = parseHeaderValue(contentType).value
  return mediaType === 'audio/wav' || mediaType === 'audio/x-wav'
}

function buildReceipt(request, body) {
  const contentType = request.headers['content-type'] || ''
  const bodyText = body.toString('latin1')
  const parts = parseMultipartParts(bodyText, contentType)
  const filePart = parts.find(part => part.name === 'file')
  return {
    method: request.method,
    url: request.url,
    authorization: request.headers.authorization || '',
    contentType,
    contentLength: body.length,
    hasMultipartFormData: parseHeaderValue(contentType).value === 'multipart/form-data',
    hasFileField: Boolean(filePart),
    hasFilename: Boolean(filePart?.filename),
    hasAudioContentType: Boolean(filePart && hasWAVContentType(filePart.contentType)),
    hasRIFF: Boolean(filePart?.bodyText.includes('RIFF')),
    hasWAVE: Boolean(filePart?.bodyText.includes('WAVE')),
    model: valueForMultipartField(parts, 'model'),
    responseFormat: valueForMultipartField(parts, 'response_format'),
    language: valueForMultipartField(parts, 'language')
  }
}

function receiptIsValid(receipt) {
  return receipt.method === 'POST'
    && receipt.url === '/v1/audio/transcriptions'
    && receipt.authorization.startsWith('Bearer ')
    && receipt.hasMultipartFormData
    && receipt.hasFileField
    && receipt.hasFilename
    && receipt.hasAudioContentType
    && receipt.hasRIFF
    && receipt.hasWAVE
    && receipt.model === expectedModel
}

const server = http.createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/v1/models') {
    sendJSON(response, 200, {
      object: 'list',
      data: [{ id: expectedModel, object: 'model', owned_by: 'foil-fixture' }]
    })
    return
  }

  if (request.method !== 'POST' || request.url !== '/v1/audio/transcriptions') {
    sendJSON(response, 404, { error: { message: 'not found' } })
    return
  }

  try {
    const body = await readBody(request)
    const receipt = buildReceipt(request, body)
    receipt.valid = receiptIsValid(receipt)

    if (receiptPath) {
      writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`)
    }

    if (!receipt.valid) {
      sendJSON(response, 400, {
        error: {
          message: 'fixture transcription request did not match expected multipart WAV contract',
          receipt
        }
      })
      return
    }

    if (receipt.responseFormat === 'json') {
      sendJSON(response, 200, { text: transcript })
    } else {
      sendText(response, 200, transcript)
    }
  } catch (error) {
    sendJSON(response, 500, { error: { message: String(error.message || error) } })
  }
})

server.listen(port, host, () => {
  const address = server.address()
  const baseURL = `http://${host}:${address.port}/v1`
  if (readyPath) {
    writeFileSync(readyPath, `${baseURL}\n`)
  }
  console.error(`fixture transcription server listening at ${baseURL}`)
})

process.on('SIGTERM', () => {
  server.close(() => process.exit(0))
})
