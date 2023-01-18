targetScope = 'managementGroup'

@description('Provide name of team or application. E.g., payroll')
param name string

@description('Provide environment.')
@allowed([
  'prod'
  'dev'
  'test'
  'qa'
])
param environment string

var subscriptionName = 'snack-${name}-${environment}'
var billingScope = '/billingAccounts/{billingAccountName}/enrollmentAccounts/{enrollmentAccountName}'

resource sub 'Microsoft.Subscription/aliases@2021-10-01' = {
  scope: tenant()
  name: subscriptionName
  properties: {
    workload: 'Production'
    displayName: subscriptionName
    billingScope: billingScope
  }
}

output subscriptionId string = sub.properties.subscriptionId
