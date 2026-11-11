import test from 'node:test'
import assert from 'node:assert/strict'
import { childrenTemplateCsv, parseChildrenCsv } from './childrenCsv.js'

test('parses child form fields and ignores imported database identifiers', () => {
  const children = parseChildrenCsv('id,org_id,branch_id,first_name,surname,date_of_birth,parent_contact,residence\nc1,o1,b1,Ada,Example,2016-05-04,Parent,North')
  assert.deepEqual(children, [{
    first_name: 'Ada',
    last_name: 'Example',
    date_of_birth: '2016-05-04',
    parent_contact: 'Parent',
    residence: 'North',
  }])
})

test('accepts optional birth date and maps guardian contact aliases', () => {
  assert.deepEqual(parseChildrenCsv('first_name,last_name,guardian_contact\nSam,Example,Guardian'), [{
    first_name: 'Sam',
    last_name: 'Example',
    date_of_birth: null,
    parent_contact: 'Guardian',
    residence: '',
  }])
})

test('rejects invalid child rows and future birth dates', () => {
  assert.throws(() => parseChildrenCsv('first_name,last_name,parent_contact\nAda,Example,'), /contact is required/)
  assert.throws(() => parseChildrenCsv('first_name,last_name,parent_contact,date_of_birth\nAda,Example,Guardian,2099-01-01'), /not in the future/)
})

test('template contains the child form fields without organization identifiers', () => {
  assert.equal(childrenTemplateCsv().replace(/^\uFEFF/, ''), 'first_name,last_name,date_of_birth,parent_contact,residence\r\n')
})
